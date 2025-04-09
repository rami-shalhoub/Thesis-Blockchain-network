#!/bin/bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#
ROOTDIR=$(cd "$(dirname "$0")" && pwd)
export PATH=${PWD}/bin:$PATH
export FABRIC_CFG_PATH=${PWD}/configtx
export VERBOSE=false

# push to the required directory & set a trap to go back if needed
pushd ${ROOTDIR} > /dev/null
trap "popd > /dev/null" EXIT

. scripts/utils.sh
: ${CONTAINER_CLI:="docker"}
if command -v ${CONTAINER_CLI}-compose > /dev/null 2>&1; then
    : ${CONTAINER_CLI_COMPOSE:="${CONTAINER_CLI}-compose"}
else
    : ${CONTAINER_CLI_COMPOSE:="${CONTAINER_CLI} compose"}
fi
infoln "Using ${CONTAINER_CLI} and ${CONTAINER_CLI_COMPOSE}"

# Obtain CONTAINER_IDS and remove them
# This function is called when you bring a network down
function clearContainers() {
    infoln "Removing remaining containers"
    ${CONTAINER_CLI} rm -f $(${CONTAINER_CLI} ps -aq --filter label=service=hyperledger-fabric) 2>/dev/null || true
    ${CONTAINER_CLI} rm -f $(${CONTAINER_CLI} ps -aq --filter name='dev-peer*') 2>/dev/null || true
    ${CONTAINER_CLI} kill "$(${CONTAINER_CLI} ps -q --filter name=ccaas)" 2>/dev/null || true
}

# Delete any images that were generated as a part of this setup
# specifically the following images are often left behind:
# This function is called when you bring the network down
function removeUnwantedImages() {
    infoln "Removing generated chaincode docker images"
    ${CONTAINER_CLI} image rm -f $(${CONTAINER_CLI} images -aq --filter reference='dev-peer*') 2>/dev/null || true
}
# Versions of fabric known not to work with the Thesis network
NONWORKING_VERSIONS="^1\.0\. ^1\.1\. ^1\.2\. ^1\.3\. ^1\.4\."

# Doing some basic sanity checking to make sure that the appropriate versions of fabric binaries/images are available.
function checkPrereqs() {
    ## Check if your have cloned the peer binaries and configuration files.
    # peer version > /dev/null 2>&1

    # if [[ $? -ne 0 || ! -d "../config" ]]; then
    #     errorln "Peer binary and configuration files not found.."
    #     errorln
    #     errorln "Follow the instructions in the Fabric docs to install the Fabric Binaries:"
    #     errorln "https://hyperledger-fabric.readthedocs.io/en/latest/install.html"
    #     exit 1
    # fi
    # use the fabric peer container to see if the samples and binaries match your docker images
    LOCAL_VERSION=$(peer version | sed -ne 's/^ Version: //p')
    DOCKER_IMAGE_VERSION=$(${CONTAINER_CLI} run --rm hyperledger/fabric-peer:latest peer version | sed -ne 's/^ Version: //p')

    infoln "LOCAL_VERSION=$LOCAL_VERSION"
    infoln "DOCKER_IMAGE_VERSION=$DOCKER_IMAGE_VERSION"

    if [ "$LOCAL_VERSION" != "$DOCKER_IMAGE_VERSION" ]; then
        warnln "Local fabric binaries and docker images are out of sync. This may cause problems."
    fi

    for UNSUPPORTED_VERSION in $NONWORKING_VERSIONS; do
        infoln "$LOCAL_VERSION" | grep -q $UNSUPPORTED_VERSION
        if [ $? -eq 0 ]; then
        fatalln "Local Fabric binary version of $LOCAL_VERSION does not match the versions supported by the network."
        fi

        infoln "$DOCKER_IMAGE_VERSION" | grep -q $UNSUPPORTED_VERSION
        if [ $? -eq 0 ]; then
        fatalln "Fabric Docker image version of $DOCKER_IMAGE_VERSION does not match the versions supported by the network."
        fi
    done
}

# Before you can bring up the network, each organization needs to generate the crypto material
# that will define that organization on the network.
function createOrgs() {
    if [ -d "orgCrypto" ]; then
        rm -Rf orgCrypto
    fi

    # Create crypto material using cryptogen
    which cryptogen
    if [ "$?" -ne 0 ]; then
        fatalln "cryptogen tool not found. exiting"
    fi
    infoln "Generating certificates using cryptogen tool"
    ################################################################################
    infoln "Creating Orderer Org Identities"
    set -x
    cryptogen generate --config=./cryptogen/crypto-config-orderer.yaml --output="orgCrypto"
    res=$?
    { set +x; } 2>/dev/null
    if [ $res -ne 0 ]; then
        fatalln "Failed to generate certificates..."
    fi
    ################################################################################
    infoln "Creating Client Org Identities"
    set -x
    cryptogen generate --config=./cryptogen/crypto-config-clientOrg.yaml --output="orgCrypto"
    res=$?
    { set +x; } 2>/dev/null
    if [ $res -ne 0 ]; then
        fatalln "Failed to generate certificates..."
    fi
    ################################################################################
    infoln "Creating Law Firm Org Identities"
    set -x
    cryptogen generate --config=./cryptogen/crypto-config-lawfirmOrg.yaml --output="orgCrypto"
    res=$?
    { set +x; } 2>/dev/null
    if [ $res -ne 0 ]; then
        fatalln "Failed to generate certificates..."
    fi
    ################################################################################
    infoln "Creating Retail Org Identities"
    set -x
    cryptogen generate --config=./cryptogen/crypto-config-retailOrg.yaml --output="orgCrypto"
    res=$?
    { set +x; } 2>/dev/null
    if [ $res -ne 0 ]; then
        fatalln "Failed to generate certificates..."
    fi
    ################################################################################
    infoln "Generating CCP files for clientOrg, lawfirmOrg, and retailOrg"
    ./ccp/ccp-generate.sh
}

# Bring up the peer and orderer nodes using docker compose.
function networkUp() {

    checkPrereqs

    # generate artifacts if they don't exist
    if [ ! -d "orgCrypto/peerOrganizations" ]; then
        createOrgs
    fi

    COMPOSE_FILES="-f compose/compose.yaml"
    DOCKER_SOCK="${DOCKER_SOCK}" ${CONTAINER_CLI_COMPOSE} ${COMPOSE_FILES} up -d 2>&1

    $CONTAINER_CLI ps -a
    if [ $? -ne 0 ]; then
        fatalln "Unable to start network"
    fi

    #Create the channels
    
    # check if all containers are present
    CONTAINERS=($($CONTAINER_CLI ps | grep hyperledger/ | awk '{print $2}'))
    len=$(echo ${#CONTAINERS[@]})

    if [[ $len -ge 4 ]] && [[ ! -d "orgCrypto/peerOrganizations" ]]; then
        echo "Bringing network down to sync certs with containers"
        networkDown
    fi

    # now run the script that creates a channel. This script uses configtxgen once
    # to create the channel creation transaction and the anchor peer updates.
    ./scripts/createChannel.sh "LawFirmClientChannel" $CLI_DELAY $MAX_RETRY $VERBOSE
    # ./scripts/createChannel.sh "RetailClientChannel" $CLI_DELAY $MAX_RETRY $VERBOSE
}

# Tear down running network
function networkDown() {
    COMPOSE_FILES="-f compose/compose.yaml"
    # COMPOSE_FILES="-f compose/compose.yaml"
    DOCKER_SOCK=$DOCKER_SOCK ${CONTAINER_CLI_COMPOSE} ${COMPOSE_FILES} ${COMPOSE_ORG3_FILES} down --volumes --remove-orphans
    #remove orderer block and other channel configuration transactions and certs
    ${CONTAINER_CLI} run --rm -v "$(pwd):/data" busybox sh -c 'cd /data && rm -rf channel-artifacts/*.block orgCrypto'        
    # ${CONTAINER_CLI} run --rm -v "$(pwd):/data" busybox sh -c 'cd /data && rm -rf channel-artifacts/*.block orgCrypto/peerOrganizations orgCrypto/ordererOrganizations'        
    # remove channel and script artifacts
    ${CONTAINER_CLI} run --rm -v "$(pwd):/data" busybox sh -c 'cd /data && rm -rf channel-artifacts log.txt *.tar.gz'
    ${CONTAINER_CLI} volume prune -f

    # Don't remove the generated artifacts -- note, the ledgers are always removed
    # if [ "$MODE" != "restart" ]; then
    #     # Bring down the network, deleting the volumes
    #     ${CONTAINER_CLI} volume rm orderer.example.com\
    #                                 anchor.client.example.com backup.client.example.com\
    #                                 anchor.lawfirm.example.com backup.lawfirm.example.com\
    #                                 anchor.retail.example.com backup.retail.example.com
    #     #Cleanup the chaincode containers
    #     clearContainers
    #     #Cleanup images
    #     removeUnwantedImages
    #     # remove orderer block and other channel configuration transactions and certs
    #     ${CONTAINER_CLI} run --rm -v "$(pwd):/data" busybox sh -c 'cd /data && rm -rf channel-artifacts/*.block orgCrypto/peerOrganizations orgCrypto/ordererOrganizations'        
    #     # remove channel and script artifacts
    #     ${CONTAINER_CLI} run --rm -v "$(pwd):/data" busybox sh -c 'cd /data && rm -rf channel-artifacts log.txt *.tar.gz'
    # fi
}

. ./network.config

# Get docker sock path from environment variable
SOCK="${DOCKER_HOST:-/var/run/docker.sock}"
DOCKER_SOCK="${SOCK##unix://}"

## Parse mode
if [[ $# -lt 1 ]] ; then
    printHelp
    exit 0
    else
    MODE=$1
    shift
fi
## if no parameters are passed, show the help for cc
if [ "$MODE" == "cc" ] && [[ $# -lt 1 ]]; then
    printHelp $MODE
    exit 0
fi

# parse subcommands if used
if [[ $# -ge 1 ]] ; then
    key="$1"
    # check for the createChannel subcommand
    if [[ "$key" == "createChannel" ]]; then
        export MODE="createChannel"
        shift
    # check for the cc command
    elif [[ "$MODE" == "cc" ]]; then
        if [ "$1" != "-h" ]; then
        export SUBCOMMAND=$key
        shift
        fi
    fi
fi


while [[ $# -ge 1 ]] ; do
    key="$1"
    case $key in
    -h )
        printHelp $MODE
        exit 0
        ;;
    -verbose )
        VERBOSE=true
        ;;
    -r )
        MAX_RETRY="$2"
        shift
        ;;
    * )
        errorln "Unknown flag: $key"
        printHelp
        exit 1
        ;;
    esac
    shift
done

# Determine mode of operation and printing out what we asked for
if [ "$MODE" == "prereq" ]; then
    infoln "Installing binaries and fabric images. Fabric Version: ${IMAGETAG}  Fabric CA Version: ${CA_IMAGETAG}"
    installPrereqs
elif [ "$MODE" == "cOrg" ]; then
    infoln "create organisations crypto"
    createOrgs
elif [ "$MODE" == "up" ]; then
    infoln "Starting nodes with CLI timeout of '${MAX_RETRY}' tries and CLI delay of '${CLI_DELAY}' seconds and using database '${DATABASE}' ${CRYPTO_MODE}"
    networkUp
elif [ "$MODE" == "down" ]; then
    infoln "Stopping network"
    networkDown
elif [ "$MODE" == "restart" ]; then
    infoln "Restarting network"
    networkDown
    networkUp
elif [ "$MODE" == "deployCC" ]; then
    infoln "deploying chaincode on channel '${CHANNEL_NAME}'"
    deployCC
elif [ "$MODE" == "deployCCAAS" ]; then
    infoln "deploying chaincode-as-a-service on channel '${CHANNEL_NAME}'"
    deployCCAAS
elif [ "$MODE" == "cc" ] && [ "$SUBCOMMAND" == "package" ]; then
    packageChaincode
elif [ "$MODE" == "cc" ] && [ "$SUBCOMMAND" == "list" ]; then
    listChaincode
elif [ "$MODE" == "cc" ] && [ "$SUBCOMMAND" == "invoke" ]; then
    invokeChaincode
elif [ "$MODE" == "cc" ] && [ "$SUBCOMMAND" == "query" ]; then
    queryChaincode
else
    printHelp
    exit 1
fi