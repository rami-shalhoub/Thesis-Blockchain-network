#!/bin/bash

# imports  
. scripts/envVar.sh
ROOTDIR=$(cd "$(dirname "$0")" && pwd)
export PATH=${PWD}/bin:$PATH
export FABRIC_CFG_PATH=${PWD}/configtx
export VERBOSE=false

CHANNEL_NAME="$1"
DELAY="$2"
MAX_RETRY="$3"
VERBOSE="$4"
: ${CHANNEL_NAME:= "LawFirmClientChannel"}
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

# createChannelArtifacts() {
# 	which configtxgen || fatalln "configtxgen tool not found."

# 	if [ -d "channel-artifacts" ]; then
#         rm -Rf channel-artifacts
#     fi
#     mkdir -p channel-artifacts

# 	set -x
# 	# # configtxgen -profile OrdererGenesis -outputBlock ./channel-artifacts/genesis.block -channelID system-channel
# 	# configtxgen -profile ${CHANNEL_NAME} -outputCreateChannelTx ./channel-artifacts/${CHANNEL_NAME}.tx -channelID ${CHANNEL_NAME}
# 	# { set +x; } 2>/dev/null

# 	# # Verify the file was created
#     # if [ ! -f "./channel-artifacts/${CHANNEL_NAME}.tx" ]; then
#     #     fatalln "Channel transaction file was not generated"
#     # fi

# 	# verifyResult $res "Failed to generate channel configuration..."

# 	# Generate genesis block for system channel
#     infoln "Generating genesis block for ${CHANNEL_NAME}"
#     configtxgen -profile OrdererGenesis -outputBlock ./channel-artifacts/genesis.block -channelID ${CHANNEL_NAME}
# 	configtxgen -profile ${CHANNEL_NAME} -outputCreateChannelTx ./channel-artifacts/${CHANNEL_NAME}/${CHANNEL_NAME}.tx -channelID ${CHANNEL_NAME}

#     res=$?
# 	{ set +x; } 2>/dev/null
#     verifyResult $res "Failed to generate system channel genesis block..."
# }

createGenesisBlock() {
	if [ -d "channel-artifacts" ]; then
        rm -Rf channel-artifacts
    fi
    mkdir -p channel-artifacts

    infoln "Generating channel creation block"
    set -x
    configtxgen -profile ${CHANNEL_NAME} -outputBlock ./channel-artifacts/${CHANNEL_NAME}.block -channelID ${CHANNEL_NAME}
    res=$?
    { set +x; } 2>/dev/null
    verifyResult $res "Failed to generate system channel genesis block"
}

# createChannelTx() {
#     infoln "Generating channel transaction for ${CHANNEL_NAME}"
#     set -x
#     configtxgen -profile ${CHANNEL_NAME} -outputCreateChannelTx ./channel-artifacts/${CHANNEL_NAME}/${CHANNEL_NAME}.tx -channelID ${CHANNEL_NAME}
#     res=$?
#     { set +x; } 2>/dev/null
#     verifyResult $res "Failed to generate channel transaction"
# }

createChannel() {
	setGlobals 1
    infoln "Creating channel ${CHANNEL_NAME}"
    set -x
    peer channel create -o orderer.example.com:6000 -c ${CHANNEL} \
        --ordererTLSHostnameOverride orderer.example.com \
        -f ./channel-artifacts/${CHANNEL}/${CHANNEL}.tx \
        --outputBlock ./channel-artifacts/${CHANNEL}/${CHANNEL}.block \
        --tls --cafile "$ORDERER_CA" >&log.txt
	# . scripts/orderer.sh ${CHANNEL_NAME} >&log.txt
    res=$?
    { set +x; } 2>/dev/null
    verifyResult $res "Channel creation failed"
}

# createChannel() {
# 	# Poll in case the raft leader is not set yet
# 	local rc=1
# 	local COUNTER=1
# 	infoln "Adding orderer"
# 	while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ] ; do
# 		sleep $DELAY
# 		set -x
# 		. scripts/orderer.sh ${CHANNEL_NAME}> /dev/null 2>&1
# 		res=$?
# 		{ set +x; } 2>/dev/null
# 		let rc=$res
# 		COUNTER=$(expr $COUNTER + 1)
# 	done
# 	cat log.txt
# 	verifyResult $res "Channel creation failed"
# }

# joinChannel ORG
joinChannel() {
    ORG=$1
    setGlobals $ORG
    local rc=1
    local COUNTER=1
    while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ]; do
        sleep $DELAY
        set -x
        peer channel join -b ./channel-artifacts/${CHANNEL_NAME}/${CHANNEL_NAME}.block >&log.txt
        res=$?
        { set +x; } 2>/dev/null
        let rc=$res
        COUNTER=$(expr $COUNTER + 1)
    done
    cat log.txt
    verifyResult $res "Peer failed to join channel '$CHANNEL_NAME'"

	#* Add the anchor peer
	setGlobals $ORG backup
	while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ] ; do
		sleep $DELAY
		set -x
		peer channel join -b ./channel-artifacts/${CHANNEL_NAME}/${CHANNEL_NAME}.block >&log.txt
		res=$?
		{ set +x; } 2>/dev/null
		let rc=$res
		COUNTER=$(expr $COUNTER + 1)
	done
	cat log.txt
	verifyResult $res "Peer failed to join channel '$CHANNEL_NAME'"
}

# joinChannel() {
# 	local ORG=$1
# 	local rc=1
# 	local COUNTER=1
# 	setGlobals $ORG
# 	## Sometimes Join takes time, hence retry
# 	while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ] ; do
# 		sleep $DELAY
# 		set -x
# 		peer channel join -b ./channel-artifacts/${CHANNEL_NAME}/genesis.block >&log.txt
# 		res=$?
# 		{ set +x; } 2>/dev/null
# 		let rc=$res
# 		COUNTER=$(expr $COUNTER + 1)
# 	done
# 	cat log.txt
# 	verifyResult $res "After $MAX_RETRY attempts, anchor.org ${ORG} has failed to join channel '$CHANNEL_NAME' "

# 	
# 	setGlobals $ORG backup
# 	while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ] ; do
# 		sleep $DELAY
# 		set -x
# 		peer channel join -b ./channel-artifacts/${CHANNEL_NAME}/genesis.block >&log.txt
# 		res=$?
# 		{ set +x; } 2>/dev/null
# 		let rc=$res
# 		COUNTER=$(expr $COUNTER + 1)
# 	done
# 	cat log.txt
# 	verifyResult $res "After $MAX_RETRY attempts, backup.org ${ORG} has failed to join channel '$CHANNEL_NAME' "

# 	cat log.txt
# 	verifyResult $res "After $MAX_RETRY attempts, anchor.org ${ORG} has failed to join channel '$CHANNEL_NAME' "
# }

setAnchorPeer() {
	ORG=$1
	. scripts/setAnchorPeer.sh $ORG $CHANNEL_NAME 
}

#~ Create channel artifacts
infoln "Generating the Genesis Block "
createGenesisBlock 

	#~ Create LawFirmClientChannel channel
	# infoln "Creating channel LawFirmClientChannel transaction file"
	# createChannelTx
	# successln "Channel LawFirmClientChannel transaction file created"

	infoln "Creating channel LawFirmClientChannel"
	createChannel
	successln "Channel LawFirmClientChannel created"

	#^ Join all the peers to the channel
	infoln "Joining ClientOrg peers to LawFirmClientChannel..."
	joinChannel 1  # ClientOrg joins

	infoln "Joining LawFirmOrg peers to LawFirmClientChannel..."
	joinChannel 2  # LawFirmOrg joins
if [ "$CHANNEL_NAME" = "LawFirmClientChannel" ]; then

else
	#~ Create RetailClientChannel channel
	infoln "Creating channel RetailClientChannel"
	createChannel
	successln "Channel RetailClientChannel created"
	#^ Join all the peers to the channel
	infoln "Joining ClientOrg peers to RetailClientChannel..."
	joinChannel 1  # ClientOrg joins 

	infoln "Joining RetailOrg peers to RetailClientChannel..."
	joinChannel 3  # RetailOrg joins
fi




## Set the anchor peers for each org in the channel
# infoln "Setting anchor peer for org1..."
# setAnchorPeer 1
# infoln "Setting anchor peer for org2..."
# setAnchorPeer 2

successln "Channels are creates and Orgs are joined"