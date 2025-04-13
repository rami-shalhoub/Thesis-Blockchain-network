#!/bin/bash
#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

# import utils
# test network home var targets to test network folder
# the reason we use a var here is considering with org3 specific folder
# when invoking this for org3 as test-network/scripts/org3-scripts
# the value is changed from default as $PWD(test-network)
# to .. as relative path to make the import works
THESIS_NETWORK_HOME=${THESIS_NETWORK_HOME:-${PWD}}
. ${THESIS_NETWORK_HOME}/scripts/envVar.sh

# fetchChannelConfig <org> <channel_id> <output_json>
# Writes the current channel config for a given channel to a JSON file
# NOTE: this requires jq and configtxlator for execution.
fetchChannelConfig() {
  ORG=$1
  CHANNEL=$2
  PROFILE=$3
  OUTPUT=$4

  setGlobals $ORG

  infoln "Fetching the most recent configuration block for the ${CHANNEL} channel"
  set -x
  peer channel fetch config ${THESIS_NETWORK_HOME}/channel-artifacts/${PROFILE}/config_block.pb -o localhost:6000 --ordererTLSHostnameOverride orderer.example.com -c $CHANNEL --tls --cafile "$ORDERER_CA"
  { set +x; } 2>/dev/null

  infoln "Decoding config block to JSON and isolating config to ${OUTPUT}"
  set -x
  configtxlator proto_decode --input ${THESIS_NETWORK_HOME}/channel-artifacts/${PROFILE}/config_block.pb --type common.Block --output ${THESIS_NETWORK_HOME}/channel-artifacts/${PROFILE}/config_block.json
  jq .data.data[0].payload.data.config ${THESIS_NETWORK_HOME}/channel-artifacts/${PROFILE}/config_block.json >"${OUTPUT}"
  res=$?
  { set +x; } 2>/dev/null
  verifyResult $res "Failed to parse ${CHANNEL} channel configuration, make sure you have jq installed"
}

# createConfigUpdate <channel_id> <original_config.json> <modified_config.json> <output.pb>
# Takes an original and modified config, and produces the config update tx
# which transitions between the two
# NOTE: this requires jq and configtxlator for execution.
createConfigUpdate() {
  CHANNEL=$1
  PROFILE=$2
  ORIGINAL=$3
  MODIFIED=$4
  OUTPUT=$5

  set -x
  configtxlator proto_encode --input "${ORIGINAL}" --type common.Config --output ${THESIS_NETWORK_HOME}/channel-artifacts/${PROFILE}/original_config.pb
  configtxlator proto_encode --input "${MODIFIED}" --type common.Config --output ${THESIS_NETWORK_HOME}/channel-artifacts/${PROFILE}/modified_config.pb
  configtxlator compute_update --channel_id "${CHANNEL}" --original ${THESIS_NETWORK_HOME}/channel-artifacts/${PROFILE}/original_config.pb --updated ${THESIS_NETWORK_HOME}/channel-artifacts/${PROFILE}/modified_config.pb --output ${THESIS_NETWORK_HOME}/channel-artifacts/${PROFILE}/config_update.pb
  configtxlator proto_decode --input ${THESIS_NETWORK_HOME}/channel-artifacts/${PROFILE}/config_update.pb --type common.ConfigUpdate --output ${THESIS_NETWORK_HOME}/channel-artifacts/${PROFILE}/config_update.json
  echo '{"payload":{"header":{"channel_header":{"channel_id":"'$CHANNEL'", "type":2}},"data":{"config_update":'$(cat ${THESIS_NETWORK_HOME}/channel-artifacts/${PROFILE}/config_update.json)'}}}' | jq . > ${THESIS_NETWORK_HOME}/channel-artifacts/${PROFILE}/config_update_in_envelope.json
  configtxlator proto_encode --input ${THESIS_NETWORK_HOME}/channel-artifacts/${PROFILE}/config_update_in_envelope.json --type common.Envelope --output "${OUTPUT}"
  { set +x; } 2>/dev/null
}

# signConfigtxAsPeerOrg <org> <configtx.pb>
# Set the peerOrg admin of an org and sign the config update
signConfigtxAsPeerOrg() {
  ORG=$1
  CONFIGTXFILE=$2
  setGlobals $ORG
  set -x
  peer channel signconfigtx -f "${CONFIGTXFILE}"
  { set +x; } 2>/dev/null
}
