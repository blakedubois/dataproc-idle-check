#!/bin/bash

readonly MY_CLUSTER_NAME="$(/usr/share/google/get_metadata_value attributes/dataproc-cluster-name)"
readonly MY_REGION="$(/usr/share/google/get_metadata_value attributes/dataproc-region)"
readonly IS_IDLE_STATUS_KEY="${MY_CLUSTER_NAME}_isIdle"
readonly IS_IDLE_STATUS_SINCE_KEY="${MY_CLUSTER_NAME}_isIdleStatusSince"
readonly IS_IDLE_STATUS_TRUE="TRUE"
readonly IS_IDLE_STATUS_FALSE="FALSE"

isActiveSSH()
{
   local isActiveSSHSession=0
   woutrow=`(w | wc -l)`
   if [[ "$woutrow" -gt 2 ]]; then
     sec=`(w | awk 'NR > 2 { print $5 }')`
     for i in $sec
       do
         if [[ $i == *.* ]]; then
           isActiveSSHSession=1
           break
         elif [[ $i == *:*m ]]; then
				   continue
         elif [[ $i == *:* ]]; then
           arrTime=(${i//:/ })
           if [[ "${arrTime[0]}"  -lt 10 ]]; then
             isActiveSSHSession=1
             break
           fi
         fi
       done
   fi
   echo "$isActiveSSHSession"
}

yarnAppsRunningOrJustFinished()
{
  local isYarnAppRunningOrJustFinishedResult=0
  appNames=$( curl -s "http://localhost:8088/ws/v1/cluster/apps?state=RUNNING"| grep -Po '"name":.*?[^\\]",')

  if [[ -n $appNames ]]; then
    # something is running
    isYarnAppRunningOrJustFinishedResult=1
  else
    jobFinishedTime=$( curl -s "http://localhost:8088/ws/v1/cluster/apps?state=FINISHED"|grep -Po '"finishedTime":.*?[^\\]"' | sort | tail -n 1 | sed 's/\"finishedTime\":\(.*\),\"/\1/' )
    if [[ -n $jobFinishedTime ]]; then
      currentTime=$(($(date +%s%N)/1000000))
      appMPH=60000
      idleTime=$(( ($currentTime - $jobFinishedTime) / $appMPH ))
      if [[ $idleTime -lt 5 ]]; then
        isYarnAppRunningOrJustFinishedResult=1
      fi
    fi
  fi

  echo "$isYarnAppRunningOrJustFinishedResult"
}

setIdleStatusIdle() {
  # Sets the isIdle metadata status and returns the timestamp of how long ago it was set to idle
  currentTime=$(($(date +%s%N)/1000000))
  local isIdleStatusSince=0

  # Get current isIdleStatus
  lastIdleStatus="$(/usr/share/google/get_metadata_value attributes/${IS_IDLE_STATUS_KEY} || echo 'FALSE')"
  if [[ "$lastIdleStatus" == "${IS_IDLE_STATUS_TRUE}"  ]]; then
    # Use the existing time stamp marking when cluster became idle 
    isIdleStatusSince="$(/usr/share/google/get_metadata_value attributes/${IS_IDLE_STATUS_SINCE_KEY} || echo 'FALSE')"
  else
    #Set isIdle to true and update the time
    gcloud compute project-info add-metadata --metadata ${IS_IDLE_STATUS_KEY}=${IS_IDLE_STATUS_TRUE},${IS_IDLE_STATUS_SINCE_KEY}=${currentTime}
    isIdleStatusSince=$currentTime
  fi

  echo "$isIdleStatusSince"
}

shutdownCluster() {
  # Remove the metadata
  gcloud compute project-info remove-metadata --keys ${IS_IDLE_STATUS_KEY},${IS_IDLE_STATUS_SINCE_KEY}

  # Shutdown the cluster
  gcloud dataproc clusters delete ${MY_CLUSTER_NAME} --quiet --region=${MY_REGION}
}

function main() {
  echo "Starting Script"

  echo "About to call check for active SSH sessions"
  isActiveSSHResult=$(isActiveSSH)
  echo "isActiveSSHResult is ${isActiveSSHResult}"
  echo "About to call check for active/recent YARN jobs"
  isYarnAppRunningOrJustFinishedResult=$(yarnAppsRunningOrJustFinished)
  echo "YARN results are ${isYarnAppRunningOrJustFinishedResult}"
  currentTime=$(($(date +%s%N)/1000000))

  if [[ ( $isActiveSSHResult -eq 0 ) && ( $isYarnAppRunningOrJustFinishedResult -eq 0 ) ]]; then
    #Set Stackdriver variable isIdle to TRUE
    isIdleSince=$(setIdleStatusIdle)
    appMPH=60000
    currentIdleTime=$(( ($currentTime - $isIdleSince) / $appMPH))
    if [[ $currentIdleTime -gt 5 ]]; then
      shutdownCluster
    fi
  else
    echo "Considering cluster ${MY_CLUSTER_NAME}  as active"
    echo $( gcloud compute project-info add-metadata --metadata ${IS_IDLE_STATUS_KEY}=${IS_IDLE_STATUS_FALSE},${IS_IDLE_STATUS_SINCE_KEY}=${currentTime})
  fi

  exit 1
}
main "$@"
