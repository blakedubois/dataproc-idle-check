# Copyright 2019 Google, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#!/bin/bash


ROLE=$(/usr/share/google/get_metadata_value attributes/dataproc-role)

function checkMaster() {
  local role="$(/usr/share/google/get_metadata_value attributes/dataproc-role)"
  local isMaster="false"
  if [[ "$role" == 'Master' ]] ; then
    isMaster="true"
  fi
  echo "$isMaster"
}

function startIdleJobChecker() {
  # check if bucket and has been passed
  local SCRIPT_STORAGE_LOCATION=$(/usr/share/google/get_metadata_value attributes/script_storage_location)
  echo "attempting to start idle checker using: ${SCRIPT_STORAGE_LOCATION}"
  if [[ -n ${SCRIPT_STORAGE_LOCATION} ]]; then
    echo "establishing isIdle process to determine when master node can be deleted"
    cd /root
    mkdir DataprocShutdown
    cd DataprocShutdown

    # copy the script from GCS
    gsutil cp "${SCRIPT_STORAGE_LOCATION}/isIdle.sh" .
    # make it executable
    chmod 700 isIdle.sh
    # run IsIdle script
    ./isIdle.sh

    #sudo bash -c 'echo "" >> /etc/crontab'
    sudo bash -c 'echo "*/2 * * * * root /root/DataprocShutdown/isIdle.sh" >> /etc/crontab'
  else
    echo "value for STORAGE_LOCATION is required"
    exit 1;
  fi
}

function main() {
  is_master_node=$(checkMaster)
  echo "Is master is $is_master_node"
  if [[ "$is_master_node" == "true" ]]; then
    startIdleJobChecker
  fi
}

main "$@"
