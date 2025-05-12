
#+ installChaincode PEER ORG
function installChaincode() {
   #~ install chaincode on anchor peer
   ORG=$1
   setGlobals $ORG
   set -x
   peer lifecycle chaincode queryinstalled --output json | jq -r 'try (.installed_chaincodes[].package_id)' | grep ^${PACKAGE_ID}$ >&log.txt
   if test $? -ne 0; then
      peer lifecycle chaincode install ${CC_NAME}.tar.gz >&log.txt
      res=$?
   fi
   { set +x; } 2>/dev/null
   cat log.txt
   verifyResult $res "Chaincode installation on anchor.org${ORG} has failed"
   successln "Chaincode is installed on anchor.org${ORG}"

   # #~ install chaincode on backup peer
   ORG=$1
   setGlobals $ORG backup
   set -x
   peer lifecycle chaincode queryinstalled --output json | jq -r 'try (.installed_chaincodes[].package_id)' | grep ^${PACKAGE_ID}$ >&log.txt
   if test $? -ne 0; then
      peer lifecycle chaincode install ${CC_NAME}.tar.gz >&log.txt
      res=$?
   fi
   { set +x; } 2>/dev/null
   cat log.txt
   verifyResult $res "Chaincode installation on backup.org${ORG} has failed"
   successln "Chaincode is installed on backup.org${ORG}"
}

#+ queryInstalled PEER ORG
function queryInstalled() {
   #~ query whether the chaincode is installed on anchor peer
   ORG=$1
   setGlobals $ORG
   set -x
   peer lifecycle chaincode queryinstalled --output json | jq -r 'try (.installed_chaincodes[].package_id)' | grep ^${PACKAGE_ID}$ >&log.txt
   res=$?
   { set +x; } 2>/dev/null
   cat log.txt
   verifyResult $res "Query installed on anchor.org${ORG} has failed"
   successln "Query installed successful on anchor.org${ORG} on channel"

   #~ query whether the chaincode is installed on backup peer
   ORG=$1
   setGlobals $ORG backup
   set -x
   peer lifecycle chaincode queryinstalled --output json | jq -r 'try (.installed_chaincodes[].package_id)' | grep ^${PACKAGE_ID}$ >&log.txt
   res=$?
   { set +x; } 2>/dev/null
   cat log.txt
   verifyResult $res "Query installed on backup.org${ORG} has failed"
   successln "Query installed successful on backup.org${ORG} on channel"
}

#+ approveForMyOrg VERSION PEER ORG
function approveForMyOrg() {
   #~ approve the chaincode definition for the organization (using anchor peer)
   ORG=$1
   setGlobals $ORG
   set -x
   peer lifecycle chaincode approveformyorg -o localhost:6000 --ordererTLSHostnameOverride orderer.example.com --tls --cafile "$ORDERER_CA" --channelID $CHANNEL_NAME --name ${CC_NAME} --version ${CC_VERSION} --package-id ${PACKAGE_ID} --sequence ${CC_SEQUENCE} ${INIT_REQUIRED} ${CC_END_POLICY} ${CC_COLL_CONFIG} >&log.txt
   res=$?
   { set +x; } 2>/dev/null
   cat log.txt
   verifyResult $res "Chaincode definition approved for org${ORG} on channel '$CHANNEL_NAME' failed"
   successln "Chaincode definition approved for org${ORG} on channel '$CHANNEL_NAME'"
}

#+ checkCommitReadiness VERSION PEER ORG
function checkCommitReadiness() {
   #~ check commit readiness on anchor peer
   ORG=$1
   shift 1
   setGlobals $ORG
   infoln "Checking the commit readiness of the chaincode definition on anchor.org${ORG} on channel '$CHANNEL_NAME'..."
   local rc=1
   local COUNTER=1
   # continue to poll
   # we either get a successful response, or reach MAX RETRY
   while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ]; do
      sleep $DELAY
      infoln "Attempting to check the commit readiness of the chaincode definition on anchor.org${ORG}, Retry after $DELAY seconds."
      set -x
      peer lifecycle chaincode checkcommitreadiness --channelID $CHANNEL_NAME --name ${CC_NAME} --version ${CC_VERSION} --sequence ${CC_SEQUENCE} ${INIT_REQUIRED} ${CC_END_POLICY} ${CC_COLL_CONFIG} --output json >&log.txt
      res=$?
      { set +x; } 2>/dev/null
      let rc=0
      # Check if all approvals are true in the JSON output
      if [ $res -eq 0 ]; then
         # Check if any "false" values exist in the approvals section
         grep '"false"' log.txt &>/dev/null && let rc=1
      else
         let rc=1
      fi
      COUNTER=$(expr $COUNTER + 1)
   done
   cat log.txt
   if test $rc -eq 0; then
      infoln "Checking the commit readiness of the chaincode definition successful on anchor.org${ORG} on channel '$CHANNEL_NAME'"
   else
      fatalln "After $MAX_RETRY attempts, Check commit readiness result on anchor.org${ORG} is INVALID!"
   fi

   #~ check commit readiness on backup peer
   setGlobals $ORG backup
   infoln "Checking the commit readiness of the chaincode definition on backup.org${ORG} on channel '$CHANNEL_NAME'..."
   local rc=1
   local COUNTER=1
   # continue to poll
   # we either get a successful response, or reach MAX RETRY
   while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ]; do
      sleep $DELAY
      infoln "Attempting to check the commit readiness of the chaincode definition on backup.org${ORG}, Retry after $DELAY seconds."
      set -x
      peer lifecycle chaincode checkcommitreadiness --channelID $CHANNEL_NAME --name ${CC_NAME} --version ${CC_VERSION} --sequence ${CC_SEQUENCE} ${INIT_REQUIRED} ${CC_END_POLICY} ${CC_COLL_CONFIG} --output json >&log.txt
      res=$?
      { set +x; } 2>/dev/null
      let rc=0
      if [ $res -eq 0 ]; then
         # Check if any "false" values exist in the approvals section
         grep '"false"' log.txt &>/dev/null && let rc=1
      else
         let rc=1
      fi
      COUNTER=$(expr $COUNTER + 1)
   done
   cat log.txt
   if test $rc -eq 0; then
      infoln "Checking the commit readiness of the chaincode definition successful on backup.org${ORG} on channel '$CHANNEL_NAME'"
   else
      fatalln "After $MAX_RETRY attempts, Check commit readiness result on backup.org${ORG} is INVALID!"
   fi
}

#+ commitChaincodeDefinition VERSION PEER ORG (PEER ORG)...
function commitChaincodeDefinition() {
   # Build peer connection parameters for anchor peers of each organization
   PEER_CONN_PARMS=()
   PEERS=""
   
   # Process each organization passed as an argument
   for ORG in "$@"
   do
      # Set globals for the anchor peer of this organization
      setGlobals $ORG "anchor"
      
      # Add peer connection parameters for this organization's anchor peer
      PEER_CONN_PARMS+=("--peerAddresses $CORE_PEER_ADDRESS")
      PEER_CONN_PARMS+=("--tlsRootCertFiles $CORE_PEER_TLS_ROOTCERT_FILE")
      
      # Build peer list for display
      if [ -z "$PEERS" ]; then
         PEERS="anchor.org${ORG}"
      else
         PEERS="$PEERS anchor.org${ORG}"
      fi
   done
   
   set -x
   peer lifecycle chaincode commit -o localhost:6000 --ordererTLSHostnameOverride orderer.example.com --tls --cafile "$ORDERER_CA" \
     --channelID $CHANNEL_NAME --name ${CC_NAME} \
     ${PEER_CONN_PARMS[@]} \
     --version ${CC_VERSION} --sequence ${CC_SEQUENCE} ${INIT_REQUIRED} ${CC_END_POLICY} ${CC_COLL_CONFIG} >&log.txt
   res=$?
   { set +x; } 2>/dev/null
   cat log.txt
   verifyResult $res "Chaincode definition commit failed on channel '$CHANNEL_NAME'"
   successln "Chaincode definition committed on channel '$CHANNEL_NAME'"
  
   # # Process each organization passed as an argument
   # PEER_CONN_PARMS=()
   # PEERS=""
   # for ORG in "$@"
   # do
   #    # Set globals for the backup peer of this organization
   #    setGlobals $ORG "backup"
      
   #    # Add peer connection parameters for this organization's backup peer
   #    PEER_CONN_PARMS+=("--peerAddresses $CORE_PEER_ADDRESS")
   #    PEER_CONN_PARMS+=("--tlsRootCertFiles $CORE_PEER_TLS_ROOTCERT_FILE")
      
   #    # Build peer list for display
   #    if [ -z "$PEERS" ]; then
   #       PEERS="backup.org${ORG}"
   #    else
   #       PEERS="$PEERS backup.org${ORG}"
   #    fi
   # done
   
   # set -x
   # peer lifecycle chaincode commit -o localhost:6000 --ordererTLSHostnameOverride orderer.example.com --tls --cafile "$ORDERER_CA" \
   #   --channelID $CHANNEL_NAME --name ${CC_NAME} \
   #   ${PEER_CONN_PARMS[@]} \
   #   --version ${CC_VERSION} --sequence $((CC_SEQUENCE + 1)) ${INIT_REQUIRED} ${CC_END_POLICY} ${CC_COLL_CONFIG} >&log.txt
   # res=$?
   # { set +x; } 2>/dev/null
   # cat log.txt
   # verifyResult $res "Chaincode definition commit failed on channel '$CHANNEL_NAME'"
   # successln "Chaincode definition committed on channel '$CHANNEL_NAME'"
}

#+ queryCommitted ORG
function queryCommitted() {
   #~ query the committed chaincode definition on anchor peer
   ORG=$1
   setGlobals $ORG
   EXPECTED_RESULT="Version: ${CC_VERSION}, Sequence: ${CC_SEQUENCE}, Endorsement Plugin: escc, Validation Plugin: vscc"
   infoln "Querying chaincode definition on anchor.org${ORG} on channel '$CHANNEL_NAME'..."
   local rc=1
   local COUNTER=1
   # continue to poll
   # we either get a successful response, or reach MAX RETRY
   while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ]; do
      sleep $DELAY
      infoln "Attempting to Query committed status on anchor.org${ORG}, Retry after $DELAY seconds."
      set -x
      peer lifecycle chaincode querycommitted --channelID $CHANNEL_NAME --name ${CC_NAME} >&log.txt
      res=$?
      { set +x; } 2>/dev/null
      test $res -eq 0 && VALUE=$(cat log.txt | grep -o '^Version: '$CC_VERSION', Sequence: [0-9]*, Endorsement Plugin: escc, Validation Plugin: vscc')
      test "$VALUE" = "$EXPECTED_RESULT" && let rc=0
      COUNTER=$(expr $COUNTER + 1)
   done
   cat log.txt
   if test $rc -eq 0; then
      successln "Query chaincode definition successful on anchor.org${ORG} on channel '$CHANNEL_NAME'"
   else
      fatalln "After $MAX_RETRY attempts, Query chaincode definition result on anchor.org${ORG} is INVALID!"
   fi

   # #~ query the committed chaincode definition on backup peer
   # ORG=$1
   # setGlobals $ORG backup
   # EXPECTED_RESULT="Version: ${CC_VERSION}, Sequence: ${CC_SEQUENCE}, Endorsement Plugin: escc, Validation Plugin: vscc"
   # infoln "Querying chaincode definition on backup.org${ORG} on channel '$CHANNEL_NAME'..."
   # local rc=1
   # local COUNTER=1
   # # continue to poll
   # # we either get a successful response, or reach MAX RETRY
   # while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ]; do
   #    sleep $DELAY
   #    infoln "Attempting to Query committed status on backup.org${ORG}, Retry after $DELAY seconds."
   #    set -x
   #    peer lifecycle chaincode querycommitted --channelID $CHANNEL_NAME --name ${CC_NAME} >&log.txt
   #    res=$?
   #    { set +x; } 2>/dev/null
   #    test $res -eq 0 && VALUE=$(cat log.txt | grep -o '^Version: '$CC_VERSION', Sequence: [0-9]*, Endorsement Plugin: escc, Validation Plugin: vscc')
   #    test "$VALUE" = "$EXPECTED_RESULT" && let rc=0
   #    COUNTER=$(expr $COUNTER + 1)
   # done
   # cat log.txt
   # if test $rc -eq 0; then
   #    successln "Query chaincode definition successful on backup.org${ORG} on channel '$CHANNEL_NAME'"
   # else
   #    fatalln "After $MAX_RETRY attempts, Query chaincode definition result on backup.org${ORG} is INVALID!"
   # fi
}

#+ Invoke the chaincode init function
function chaincodeInvokeInit() {
   parsePeerConnectionParameters $@
   res=$?
   verifyResult $res "Invoke transaction failed on channel '$CHANNEL_NAME' due to uneven number of peer and org parameters "

   local rc=1
   local COUNTER=1
   local fcn_call='{"function":"'${CC_INIT_FCN}'","Args":[]}'
   # continue to poll
   # we either get a successful response, or reach MAX RETRY
   while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ]; do
      sleep $DELAY
      # while 'peer chaincode' command can get the orderer endpoint from the
      # peer (if join was successful), let's supply it directly as we know
      # it using the "-o" option
      set -x
      infoln "invoke fcn call:${fcn_call}"
      peer chaincode invoke -o localhost:6000 --ordererTLSHostnameOverride orderer.example.com --tls --cafile "$ORDERER_CA" -C $CHANNEL_NAME -n ${CC_NAME} "${PEER_CONN_PARMS[@]}" --isInit -c ${fcn_call} >&log.txt
      res=$?
      { set +x; } 2>/dev/null
      let rc=$res
      COUNTER=$(expr $COUNTER + 1)
   done
   cat log.txt
   verifyResult $res "Invoke execution on $PEERS failed "
   successln "Invoke transaction successful on $PEERS on channel '$CHANNEL_NAME'"
}

function chaincodeQuery() {
   ORG=$1
   setGlobals $ORG
   infoln "Querying on peer0.org${ORG} on channel '$CHANNEL_NAME'..."
   local rc=1
   local COUNTER=1
   # continue to poll
   # we either get a successful response, or reach MAX RETRY
   while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ]; do
      sleep $DELAY
      infoln "Attempting to Query peer0.org${ORG}, Retry after $DELAY seconds."
      set -x
      peer chaincode query -C $CHANNEL_NAME -n ${CC_NAME} -c '{"Args":["org.hyperledger.fabric:GetMetadata"]}' >&log.txt
      res=$?
      { set +x; } 2>/dev/null
      let rc=$res
      COUNTER=$(expr $COUNTER + 1)
   done
   cat log.txt
   if test $rc -eq 0; then
      successln "Query successful on peer0.org${ORG} on channel '$CHANNEL_NAME'"
   else
      fatalln "After $MAX_RETRY attempts, Query result on peer0.org${ORG} is INVALID!"
   fi
}

function resolveSequence() {

   #if the sequence is not "auto", then use the provided sequence
   if [[ "${CC_SEQUENCE}" != "auto" ]]; then
      return 0
   fi

   local rc=1
   local COUNTER=1

   # first, find the sequence number of the committed chaincode
   # we either get a successful response, or reach MAX RETRY
   while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ]; do
      set -x
      COMMITTED_CC_SEQUENCE=$(peer lifecycle chaincode querycommitted --channelID $CHANNEL_NAME --name ${CC_NAME} | sed -n "/Version:/{s/.*Sequence: //; s/, Endorsement Plugin:.*$//; p;}")
      res=$?
      { set +x; } 2>/dev/null
      let rc=$res
      COUNTER=$(expr $COUNTER + 1)
   done

   # if there are no committed versions, then set the sequence to 1
   if [ -z $COMMITTED_CC_SEQUENCE ]; then
      CC_SEQUENCE=1
      return 0
   fi

   rc=1
   COUNTER=1
   # next, find the sequence number of the approved chaincode
   # we either get a successful response, or reach MAX RETRY
   while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ]; do
      set -x
      APPROVED_CC_SEQUENCE=$(peer lifecycle chaincode queryapproved --channelID $CHANNEL_NAME --name ${CC_NAME} | sed -n "/sequence:/{s/^sequence: //; s/, version:.*$//; p;}")
      res=$?
      { set +x; } 2>/dev/null
      let rc=$res
      COUNTER=$(expr $COUNTER + 1)
   done

   # if the committed sequence and the approved sequence match, then increment the sequence
   # otherwise, use the approved sequence
   if [ $COMMITTED_CC_SEQUENCE == $APPROVED_CC_SEQUENCE ]; then
      CC_SEQUENCE=$((COMMITTED_CC_SEQUENCE + 1))
   else
      CC_SEQUENCE=$APPROVED_CC_SEQUENCE
   fi

}

#. scripts/envVar.sh

queryInstalledOnPeer() {

   local rc=1
   local COUNTER=1
   # continue to poll
   # we either get a successful response, or reach MAX RETRY
   while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ]; do
      #sleep $DELAY
      #infoln "Attempting to list on peer0.org${ORG}, Retry after $DELAY seconds."
      peer lifecycle chaincode queryinstalled >&log.txt
      res=$?
      let rc=$res
      COUNTER=$(expr $COUNTER + 1)
   done
   cat log.txt
}

queryCommittedOnChannel() {
   CHANNEL=$1
   local rc=1
   local COUNTER=1
   # continue to poll
   # we either get a successful response, or reach MAX RETRY
   while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ]; do
      #sleep $DELAY
      #infoln "Attempting to list on peer0.org${ORG}, Retry after $DELAY seconds."
      peer lifecycle chaincode querycommitted -C $CHANNEL >&log.txt
      res=$?
      let rc=$res
      COUNTER=$(expr $COUNTER + 1)
   done
   cat log.txt
   if test $rc -ne 0; then
      fatalln "After $MAX_RETRY attempts, Failed to retrieve committed chaincode!"
   fi

}

## Function to list chaincodes installed on the peer and committed chaincode visible to the org
listAllCommitted() {

   local rc=1
   local COUNTER=1
   # continue to poll
   # we either get a successful response, or reach MAX RETRY
   while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ]; do
      CHANNEL_LIST=$(peer channel list | sed '1,1d')
      res=$?
      let rc=$res
      COUNTER=$(expr $COUNTER + 1)
   done
   if test $rc -eq 0; then
      for channel in $CHANNEL_LIST; do
         queryCommittedOnChannel "$channel"
      done
   else
      fatalln "After $MAX_RETRY attempts, Failed to retrieve committed chaincode!"
   fi

}

chaincodeInvoke() {
   ORG=$1
   CHANNEL=$2
   CC_NAME=$3
   CC_INVOKE_CONSTRUCTOR=$4

   infoln "Invoking on peer0.org${ORG} on channel '$CHANNEL_NAME'..."
   local rc=1
   local COUNTER=1
   # continue to poll
   # we either get a successful response, or reach MAX RETRY
   while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ]; do
      sleep $DELAY
      infoln "Attempting to Invoke on peer0.org${ORG}, Retry after $DELAY seconds."
      set -x
      peer chaincode invoke -o localhost:7050 -C $CHANNEL_NAME -n ${CC_NAME} -c ${CC_INVOKE_CONSTRUCTOR} --tls --cafile $ORDERER_CA --peerAddresses localhost:7051 --tlsRootCertFiles $PEER0_ORG1_CA --peerAddresses localhost:9051 --tlsRootCertFiles $PEER0_ORG2_CA >&log.txt
      res=$?
      { set +x; } 2>/dev/null
      let rc=$res
      COUNTER=$(expr $COUNTER + 1)
   done
   cat log.txt
   if test $rc -eq 0; then
      successln "Invoke successful on peer0.org${ORG} on channel '$CHANNEL_NAME'"
   else
      fatalln "After $MAX_RETRY attempts, Invoke result on peer0.org${ORG} is INVALID!"
   fi
}

chaincodeQuery() {
   ORG=$1
   CHANNEL=$2
   CC_NAME=$3
   CC_QUERY_CONSTRUCTOR=$4

   infoln "Querying on peer0.org${ORG} on channel '$CHANNEL_NAME'..."
   local rc=1
   local COUNTER=1
   # continue to poll
   # we either get a successful response, or reach MAX RETRY
   while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ]; do
      sleep $DELAY
      infoln "Attempting to Query peer0.org${ORG}, Retry after $DELAY seconds."
      set -x
      peer chaincode query -C $CHANNEL_NAME -n ${CC_NAME} -c ${CC_QUERY_CONSTRUCTOR} >&log.txt
      res=$?
      { set +x; } 2>/dev/null
      let rc=$res
      COUNTER=$(expr $COUNTER + 1)
   done
   cat log.txt
   if test $rc -eq 0; then
      successln "Query successful on peer0.org${ORG} on channel '$CHANNEL_NAME'"
   else
      fatalln "After $MAX_RETRY attempts, Query result on peer0.org${ORG} is INVALID!"
   fi
}
