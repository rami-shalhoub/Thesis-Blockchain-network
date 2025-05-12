#!/usr/bin/env bash
#
#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

source scripts/utils.sh

CHANNEL_NAME=${1}
CC_NAME=${2}
CC_SRC_PATH=${3}
CCAAS_DOCKER_RUN=${4:-"true"}
CC_VERSION=${5:-"1.0"}
CC_SEQUENCE=${6:-"1"}
CC_INIT_FCN=${7:-"NA"}
CC_END_POLICY=${8:-"NA"}
CC_COLL_CONFIG=${9:-"NA"}
DELAY=${10:-"3"}
MAX_RETRY=${11:-"5"}
VERBOSE=${12:-"false"}
CCAAS_SERVER_PORT=${13}
Org_1=${14}
Org_2=${15}

: ${CONTAINER_CLI:="docker"}
if command -v ${CONTAINER_CLI}-compose >/dev/null 2>&1; then
   : ${CONTAINER_CLI_COMPOSE:="${CONTAINER_CLI}-compose"}
else
   : ${CONTAINER_CLI_COMPOSE:="${CONTAINER_CLI} compose"}
fi
infoln "Using ${CONTAINER_CLI} and ${CONTAINER_CLI_COMPOSE}"

println "executing with the following"
println "- CHANNEL_NAME: ${C_GREEN}${CHANNEL_NAME}${C_RESET}"
println "- CC_NAME: ${C_GREEN}${CC_NAME}${C_RESET}"
println "- CC_SRC_PATH: ${C_GREEN}${CC_SRC_PATH}${C_RESET}"
println "- CC_VERSION: ${C_GREEN}${CC_VERSION}${C_RESET}"
println "- CC_SEQUENCE: ${C_GREEN}${CC_SEQUENCE}${C_RESET}"
println "- CC_END_POLICY: ${C_GREEN}${CC_END_POLICY}${C_RESET}"
println "- CC_COLL_CONFIG: ${C_GREEN}${CC_COLL_CONFIG}${C_RESET}"
println "- CC_INIT_FCN: ${C_GREEN}${CC_INIT_FCN}${C_RESET}"
println "- CCAAS_DOCKER_RUN: ${C_GREEN}${CCAAS_DOCKER_RUN}${C_RESET}"
println "- DELAY: ${C_GREEN}${DELAY}${C_RESET}"
println "- MAX_RETRY: ${C_GREEN}${MAX_RETRY}${C_RESET}"
println "- VERBOSE: ${C_GREEN}${VERBOSE}${C_RESET}"
println "- CCAAS_SERVER_PORT: ${C_GREEN}${CCAAS_SERVER_PORT}${C_RESET}"

#User has not provided a name
if [ -z "$CC_NAME" ] || [ "$CC_NAME" = "NA" ]; then
   fatalln "No chaincode name was provided. Valid call example: ./network.sh deployCCAS -ccn basic -ccp ../asset-transfer-basic/chaincode-go "

# User has not provided a path
elif [ -z "$CC_SRC_PATH" ] || [ "$CC_SRC_PATH" = "NA" ]; then
   fatalln "No chaincode path was provided. Valid call example: ./network.sh deployCCAS -ccn basic -ccp ../asset-transfer-basic/chaincode-go "

## Make sure that the path to the chaincode exists
elif [ ! -d "$CC_SRC_PATH" ]; then
   fatalln "Path to chaincode does not exist. Please provide different path."
fi

if [ "$CC_END_POLICY" = "NA" ]; then
   CC_END_POLICY=""
else
   CC_END_POLICY="--signature-policy $CC_END_POLICY"
fi

if [ "$CC_COLL_CONFIG" = "NA" ]; then
   CC_COLL_CONFIG=""
else
   CC_COLL_CONFIG="--collections-config $CC_COLL_CONFIG"
fi

# import utils
. scripts/envVar.sh
. scripts/ccutils.sh

packageChaincode() {

   address="{{.peername}}_${CC_NAME}_ccaas:${CCAAS_SERVER_PORT}"
   prefix=$(basename "$0")
   tempdir=$(mktemp -d -t "$prefix.XXXXXXXX") || error_exit "Error creating temporary directory"
   label=${CC_NAME}_${CC_VERSION}
   mkdir -p "$tempdir/src"

   cat >"$tempdir/src/connection.json" <<CONN_EOF
{
  "address": "${address}",
  "dial_timeout": "10s",
  "tls_required": false
}
CONN_EOF

   mkdir -p "$tempdir/pkg"

   cat <<METADATA-EOF >"$tempdir/pkg/metadata.json"
{
    "type": "ccaas",
    "label": "$label"
}
METADATA-EOF

   tar -C "$tempdir/src" -czf "$tempdir/pkg/code.tar.gz" .
   tar -C "$tempdir/pkg" -czf "$CC_NAME.tar.gz" metadata.json code.tar.gz
   rm -Rf "$tempdir"

   PACKAGE_ID=$(peer lifecycle chaincode calculatepackageid ${CC_NAME}.tar.gz)

   successln "Chaincode is packaged  ${address}"
}

buildDockerImages() {
   FABRIC_CFG_PATH=${1}

   # if set don't build - useful when you want to debug yourself
   if [ "$CCAAS_DOCKER_RUN" = "true" ]; then
      # build the docker container
      infoln "Building Chaincode-as-a-Service docker image '${CC_NAME}' '${CC_SRC_PATH}'"
      infoln "This may take several minutes..."
      set -x
      ${CONTAINER_CLI} build -f $CC_SRC_PATH/dockerfile -t ${CC_NAME}_ccaas_image:latest --build-arg CC_SERVER_PORT=$CCAAS_SERVER_PORT $CC_SRC_PATH >&log.txt
      res=$?
      { set +x; } 2>/dev/null
      cat log.txt
      verifyResult $res "Docker build of chaincode-as-a-service container failed"
      successln "Docker image '${CC_NAME}_ccaas_image:latest' built succesfully"
   else
      infoln "Not building docker image; this the command we would have run"
      infoln "   ${CONTAINER_CLI} build -f $CC_SRC_PATH/Dockerfile -t ${CC_NAME}_ccaas_image:latest --build-arg CC_SERVER_PORT=$CCAAS_SERVER_PORT $CC_SRC_PATH"
   fi
}

startDockerContainer() {
   # start the docker container
   if [ "$CCAAS_DOCKER_RUN" = "true" ]; then
      infoln "Starting the Chaincode-as-a-Service docker container..."
      set -x
      ${CONTAINER_CLI} run -d --name anchor_${Org_1}_${CC_NAME}_ccaas \
         --network fabric_thesis \
         -e CHAINCODE_SERVER_ADDRESS=0.0.0.0:${CCAAS_SERVER_PORT} \
         -e CHAINCODE_ID=$PACKAGE_ID -e CORE_CHAINCODE_ID_NAME=$PACKAGE_ID \
         ${CC_NAME}_ccaas_image:latest

      ${CONTAINER_CLI} run -d --name backup_${Org_1}_${CC_NAME}_ccaas \
         --network fabric_thesis \
         -e CHAINCODE_SERVER_ADDRESS=0.0.0.0:${CCAAS_SERVER_PORT} \
         -e CHAINCODE_ID=$PACKAGE_ID -e CORE_CHAINCODE_ID_NAME=$PACKAGE_ID \
         ${CC_NAME}_ccaas_image:latest
      res=$?

      ${CONTAINER_CLI} run -d --name anchor_${Org_2}_${CC_NAME}_ccaas \
         --network fabric_thesis \
         -e CHAINCODE_SERVER_ADDRESS=0.0.0.0:${CCAAS_SERVER_PORT} \
         -e CHAINCODE_ID=$PACKAGE_ID -e CORE_CHAINCODE_ID_NAME=$PACKAGE_ID \
         ${CC_NAME}_ccaas_image:latest

      ${CONTAINER_CLI} run -d --name backup_${Org_2}_${CC_NAME}_ccaas \
         --network fabric_thesis \
         -e CHAINCODE_SERVER_ADDRESS=0.0.0.0:${CCAAS_SERVER_PORT} \
         -e CHAINCODE_ID=$PACKAGE_ID -e CORE_CHAINCODE_ID_NAME=$PACKAGE_ID \
         ${CC_NAME}_ccaas_image:latest
      res=$?
      { set +x; } 2>/dev/null
      cat log.txt
      verifyResult $res "Failed to start the container container '${CC_NAME}_ccaas_image:latest' "
      successln "Docker container started succesfully '${CC_NAME}_ccaas_image:latest'"
   else

      infoln "Not starting docker containers; these are the commands we would have run"
      infoln "    ${CONTAINER_CLI} run --rm -d --name peer0org1_${CC_NAME}_ccaas  \
                  --network fabric_test \
                  -e CHAINCODE_SERVER_ADDRESS=0.0.0.0:${CCAAS_SERVER_PORT} \
                  -e CHAINCODE_ID=$PACKAGE_ID -e CORE_CHAINCODE_ID_NAME=$PACKAGE_ID \
                    ${CC_NAME}_ccaas_image:latest"
      infoln "    ${CONTAINER_CLI} run --rm -d --name peer0org2_${CC_NAME}_ccaas  \
                  --network fabric_test \
                  -e CHAINCODE_SERVER_ADDRESS=0.0.0.0:${CCAAS_SERVER_PORT} \
                  -e CHAINCODE_ID=$PACKAGE_ID -e CORE_CHAINCODE_ID_NAME=$PACKAGE_ID \
                    ${CC_NAME}_ccaas_image:latest"

   fi
}

if [ "$CC_NAME" == "lawfirmclientcc" ]; then

   # Build the docker image
   buildDockerImages "$PWD/docker/peercfg/client.example.com/anchor.client.example.com"
   buildDockerImages "$PWD/docker/peercfg/client.example.com/backup.client.example.com"

   buildDockerImages "$PWD/docker/peercfg/lawfirm.example.com/anchor.lawfirm.example.com"
   buildDockerImages "$PWD/docker/peercfg/lawfirm.example.com/backup.lawfirm.example.com"

   ## package the chaincode
   packageChaincode

   ## Install chaincode on ClientOtg and LawFirmOrg peers
   infoln "Installing chaincode on ClientOrg..."
   installChaincode 1
   infoln "Install chaincode on LawFirmOrg..."
   installChaincode 2

   resolveSequence

   ## query whether the chaincode is installed
   infoline "Querying chaincode on ClientOrg..."
   queryInstalled 1
   infoline "Querying chaincode on LawFirmOrg..."
   queryInstalled 2

   ## approve the definition for org1
   infoln "Approving chaincode for ClientOrg..."
   approveForMyOrg 1

   ## check whether the chaincode definition is ready to be committed
   ## expect ClientOrg to have approved and LawFirmOrg not to
   infoln "Checking commit readiness for ClientOrg and LawFirmOrg..."
   checkCommitReadiness 1 #"\"ClientOrgMSP\": true" "\"LawFirmOrgMSP\": false"
   checkCommitReadiness 2 #"\"ClientOrgMSP\": true" "\"LawFirmOrgMSP\": false"

   infoln "Approving chaincode for LawFirmOrg..."
   approveForMyOrg 2
   # ## check whether the chaincode definition is ready to be committed
   # ## expect ClientOrg to have approved and LawFirmOrg not to
   infoln "Checking commit readiness for LawFirmOrg..."
   checkCommitReadiness 1 #"\"ClientOrgMSP\": true" "\"LawFirmOrgMSP\": true"
   checkCommitReadiness 2 #"\"ClientOrgMSP\": true" "\"LawFirmOrgMSP\": true"

   # ## now that we know for sure both orgs have approved, commit the definition
   commitChaincodeDefinition 1 2


   ## query on both orgs to see that the definition committed successfully
   queryCommitted 1
   queryCommitted 2

   # start the container
   startDockerContainer

   ## Invoke the chaincode - this does require that the chaincode have the 'initLedger'
   ## method defined
   if [ "$CC_INIT_FCN" = "NA" ]; then
      infoln "Chaincode initialization is not required"
   else
      chaincodeInvokeInit 1 2
   fi

   exit 0
else
   # Build the docker image
   buildDockerImages "$PWD/docker/peercfg/client.example.com/anchor.client.example.com"
   buildDockerImages "$PWD/docker/peercfg/client.example.com/backup.client.example.com"

   buildDockerImages "$PWD/docker/peercfg/retail.example.com/anchor.retail.example.com"
   buildDockerImages "$PWD/docker/peercfg/retail.example.com/backup.retail.example.com"

   ## package the chaincode
   packageChaincode

   ## Install chaincode on ClientOtg and RetailOrg peers
   infoln "Installing chaincode on ClientOrg..."
   installChaincode 1
   infoln "Install chaincode on RetailOrg..."
   installChaincode 3

   resolveSequence
   ## query whether the chaincode is installed
   infoline "Querying chaincode on ClientOrg..."
   queryInstalled 1
   infoline "Querying chaincode on RetailOrg..."
   queryInstalled 3

   ## approve the definition for org1
   infoln "Approving chaincode for ClientOrg..."
   approveForMyOrg 1

   ## check whether the chaincode definition is ready to be committed
   ## expect ClientOrg to have approved and RetailOrg not to
   infoln "Checking commit readiness for ClientOrg and RetailOrg..."
   checkCommitReadiness 1 #"\"ClientOrgMSP\": true" "\"RetailOrgMSP\": false"
   checkCommitReadiness 3 #"\"ClientOrgMSP\": true" "\"RetailOrgMSP\": false"

   ## now approve also for RetailOrg
   infoln "Approving chaincode for RetailOrg..."
   approveForMyOrg 3

   ## check whether the chaincode definition is ready to be committed
   ## expect ClientOrg to have approved and RetailOrg not to
   checkCommitReadiness 1 #"\"ClientOrgMSP\": true" "\"RetailOrgMSP\": true"
   checkCommitReadiness 3 #\"ClientOrgMSP\": true" "\"RetailOrgMSP\": true"

   ## now that we know for sure both orgs have approved, commit the definition
   commitChaincodeDefinition 1 3

   ## query on both orgs to see that the definition committed successfully
   queryCommitted 1
   queryCommitted 3

   # start the container
   startDockerContainer

   ## Invoke the chaincode - this does require that the chaincode have the 'initLedger'
   ## method defined
   if [ "$CC_INIT_FCN" = "NA" ]; then
      infoln "Chaincode initialization is not required"
   else
      chaincodeInvokeInit 1 3
   fi

   exit 0
fi
