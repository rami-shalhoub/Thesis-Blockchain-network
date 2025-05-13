#!/bin/bash
#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

THESIS_NETWORK_HOME=${THESIS_NETWORK_HOME:-${PWD}}
. ${THESIS_NETWORK_HOME}/scripts/configUpdate.sh

# NOTE: This requires jq and configtxlator for execution.
createAnchorPeerUpdate() {
   infoln "Fetching channel config for channel $CHANNEL_NAME"
   fetchChannelConfig $ORG $CHANNEL_NAME $PROFILE ${THESIS_NETWORK_HOME}/channel-artifacts/${PROFILE}/${CORE_PEER_LOCALMSPID}config.json

   infoln "Generating anchor peer update transaction for Org${ORG} on channel $CHANNEL_NAME"

   if [ $ORG -eq 1 ]; then
      HOST="anchor.client.example.com"
      PORT=7000
   elif [ $ORG -eq 2 ]; then
      HOST="anchor.lawfirm.example.com"
      PORT=8000
   elif [ $ORG -eq 3 ]; then
      HOST="anchor.retail.example.com"
      PORT=9000
   else
      errorln "Org${ORG} unknown"
   fi

   set -x
   # Modify the configuration to append the anchor peer
   jq '.channel_group.groups.Application.groups.'${CORE_PEER_LOCALMSPID}'.values += {"AnchorPeers":{"mod_policy": "Admins","value":{"anchor_peers": [{"host": "'$HOST'","port": '$PORT'}]},"version": "0"}}' ${THESIS_NETWORK_HOME}/channel-artifacts/${PROFILE}/${CORE_PEER_LOCALMSPID}config.json >${THESIS_NETWORK_HOME}/channel-artifacts/${PROFILE}/${CORE_PEER_LOCALMSPID}modified_config.json
   res=$?
   { set +x; } 2>/dev/null
   verifyResult $res "Channel configuration update for anchor peer failed, make sure you have jq installed"

   # Compute a config update, based on the differences between
   # {orgmsp}config.json and {orgmsp}modified_config.json, write
   # it as a transaction to {orgmsp}anchors.tx
   createConfigUpdate ${CHANNEL_NAME} ${PROFILE} ${THESIS_NETWORK_HOME}/channel-artifacts/${PROFILE}/${CORE_PEER_LOCALMSPID}config.json ${THESIS_NETWORK_HOME}/channel-artifacts/${PROFILE}/${CORE_PEER_LOCALMSPID}modified_config.json ${THESIS_NETWORK_HOME}/channel-artifacts/${PROFILE}/${CORE_PEER_LOCALMSPID}anchors.tx
}

updateAnchorPeer() {
   peer channel update -o localhost:6000 --ordererTLSHostnameOverride orderer.example.com -c $CHANNEL_NAME -f ${THESIS_NETWORK_HOME}/channel-artifacts/${PROFILE}/${CORE_PEER_LOCALMSPID}anchors.tx --tls --cafile "$ORDERER_CA" >&log.txt
   res=$?
   cat log.txt
   verifyResult $res "Anchor peer update failed"
   successln "Anchor peer set for org '$CORE_PEER_LOCALMSPID' on channel '$CHANNEL_NAME'"
}

ORG=$1
CHANNEL_NAME=$2
PROFILE=$3

setGlobals $ORG

createAnchorPeerUpdate

updateAnchorPeer
