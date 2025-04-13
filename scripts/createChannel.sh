#!/bin/bash

# imports  
. scripts/envVar.sh
ROOTDIR=$(cd "$(dirname "$0")" && pwd)
export PATH=${PWD}/bin:$PATH
export FABRIC_CFG_PATH=${PWD}/configtx

CHANNEL_NAME="$1"
DELAY="$2"
MAX_RETRY="$3"
VERBOSE="$4"
PROFILE="$5"
: ${DELAY:="3"}
: ${MAX_RETRY:="5"}
: ${VERBOSE:="false"}
: ${CONTAINER_CLI:="docker"}
if command -v ${CONTAINER_CLI}-compose > /dev/null 2>&1; then
    : ${CONTAINER_CLI_COMPOSE:="${CONTAINER_CLI}-compose"}
else
    : ${CONTAINER_CLI_COMPOSE:="${CONTAINER_CLI} compose"}
fi
infoln "Using ${CONTAINER_CLI} and ${CONTAINER_CLI_COMPOSE}"


createGenesisBlock() {
    set -x
    configtxgen -profile ${PROFILE} -outputBlock ${BLOCKFILE} -channelID ${CHANNEL_NAME}
    res=$?
    { set +x; } 2>/dev/null
    verifyResult $res "Failed to generate system channel genesis block"
}

createChannel() {
	setGlobals 1
    set -x
	. scripts/orderer.sh ${CHANNEL_NAME} ${PROFILE} ${BLOCKFILE}> /dev/null 2>&1
    res=$?
    { set +x; } 2>/dev/null
    verifyResult $res "Channel creation failed"
}

# joinChannel ORG
joinChannel() {
    ORG=$1
    local rc=1
    local COUNTER=1

    setGlobals $ORG
	infoln "Joining the anchor peer to $CHANNEL_NAME.. "
    while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ]; do
        sleep $DELAY
        set -x
		peer channel join -b $BLOCKFILE >&log.txt
        res=$?
        { set +x; } 2>/dev/null
        let rc=$res
        COUNTER=$(expr $COUNTER + 1)
    done
    cat log.txt
    verifyResult $res "Anchor Peer failed to join channel '$CHANNEL_NAME'"

	#* Add the anchor peer
	setGlobals $ORG backup
	infoln "Joining the backup peer to $CHANNEL_NAME.. "
	while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ] ; do
		sleep $DELAY
		set -x
		peer channel join -b ./channel-artifacts/${PROFILE}/${CHANNEL_NAME}.block >&log.txt
		res=$?
		{ set +x; } 2>/dev/null
		let rc=$res
		COUNTER=$(expr $COUNTER + 1)
	done
	cat log.txt
	verifyResult $res "Backup Peer failed to join channel '$CHANNEL_NAME'"
}

setAnchorPeer() {
	ORG=$1
	. scripts/setAnchorPeer.sh $ORG $CHANNEL_NAME $PROFILE
}

#~ Create channel Genesis Block
infoln "Generating channel genesis block '${CHANNEL_NAME}.block'"
BLOCKFILE="./channel-artifacts/${PROFILE}/${CHANNEL_NAME}.block"
createGenesisBlock 

#~ Creatig the channel
infoln "Creating channel ${CHANNEL_NAME}"
createChannel
successln "Channel ${CHANNEL_NAME} created"
if [ "$PROFILE" == "LawFirmClientChannel" ]; then
	#^ Join all the peers to the channel
	infoln "Joining ClientOrg peers to LawFirmClientChannel..."
	joinChannel 1  # ClientOrg joins

	infoln "Joining LawFirmOrg peers to LawFirmClientChannel..."
	joinChannel 2  # LawFirmOrg joins

	#^ Set the anchor peers for each org in the channel
	infoln "Setting anchor peer for ClientOrg..."
	setAnchorPeer 1
	infoln "Setting anchor peer for LawFirmOrg..."
	setAnchorPeer 2
else
	#^ Join all the peers to the channel
	infoln "Joining ClientOrg peers to RetailClientChannel..."
	joinChannel 1  # ClientOrg joins 

	infoln "Joining RetailOrg peers to RetailClientChannel..."
	joinChannel 3  # RetailOrg joins
	
	#^ Set the anchor peers for each org in the channel
	infoln "Setting anchor peer for ClientOrg..."
	setAnchorPeer 1
	infoln "Setting anchor peer for RetailOrg..."
	setAnchorPeer 3
fi





successln "Channels are creates and Orgs are joined"