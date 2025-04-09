#!/bin/bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#
# This is a collection of bash functions used by different scripts

# imports
THESIS_NETWORK_HOME=${THESIS_NETWORK_HOME:-${PWD}}
. ${THESIS_NETWORK_HOME}/scripts/utils.sh

export CORE_PEER_TLS_ENABLED=true
export ORDERER_CA=${THESIS_NETWORK_HOME}/orgCrypto/ordererOrganizations/example.com/tlsca/tlsca.example.com-cert.pem
export CLIENT_CA=${THESIS_NETWORK_HOME}/orgCrypto/peerOrganizations/client.example.com/tlsca/tlsca.client.example.com-cert.pem
export LAWFIRM_CA=${THESIS_NETWORK_HOME}/orgCrypto/peerOrganizations/lawfirm.example.com/tlsca/tlsca.lawfirm.example.com-cert.pem
export RETAIL_CA=${THESIS_NETWORK_HOME}/orgCrypto/peerOrganizations/retail.example.com/tlsca/tlsca.retail.example.com-cert.pem

# Set environment variables for the peer org
setGlobals() {
  local USING_ORG=""
  if [ -z "$OVERRIDE_ORG" ]; then
    USING_ORG=$1
  else
    USING_ORG="${OVERRIDE_ORG}"
  fi
  local PEER_TYPE=${2:-"anchor"}  # Default to anchor peer
  infoln "Using organization ${USING_ORG}"
  case $USING_ORG in
    1)
      export CORE_PEER_LOCALMSPID=ClientOrgMSP
      export CORE_PEER_TLS_ROOTCERT_FILE=$CLIENT_CA
      export CORE_PEER_MSPCONFIGPATH=${THESIS_NETWORK_HOME}/orgCrypto/peerOrganizations/client.example.com/users/Admin@client.example.com/msp
      if [ "$PEER_TYPE" = "anchor" ]; then
        export CORE_PEER_ADDRESS=localhost:7000
      else
        export CORE_PEER_ADDRESS=localhost:7010
      fi
      ;;
    2)
      export CORE_PEER_LOCALMSPID=LawFirmOrgMSP
      export CORE_PEER_TLS_ROOTCERT_FILE=$LAWFIRM_CA
      export CORE_PEER_MSPCONFIGPATH=${THESIS_NETWORK_HOME}/orgCrypto/peerOrganizations/lawfirm.example.com/users/Admin@lawfirm.example.com/msp
      if [ "$PEER_TYPE" = "anchor" ]; then
        export CORE_PEER_ADDRESS=localhost:8000
      else
        export CORE_PEER_ADDRESS=localhost:8010
      fi
      ;;
    3)
      export CORE_PEER_LOCALMSPID=RetailOrgMSP
      export CORE_PEER_TLS_ROOTCERT_FILE=$RETIAL_CA
      export CORE_PEER_MSPCONFIGPATH=${THESIS_NETWORK_HOME}/orgCrypto/peerOrganizations/retail.example.com/users/Admin@retail.example.com/msp
      if [ "$PEER_TYPE" = "anchor" ]; then
        export CORE_PEER_ADDRESS=localhost:9000
      else
        export CORE_PEER_ADDRESS=localhost:9010
      fi
      ;;
    *)  errorln "ORG Unknown"
  esac

  if [ "$VERBOSE" = "true" ]; then
    env | grep CORE
  fi
}

parsePeerConnectionParameters() {
  PEER_CONN_PARMS=()
  PEERS=""
  while [ "$#" -gt 0 ]; do
    local ORG=$1
    local PEER_TYPE=${2:-"anchor"}  # Default to anchor peer
    setGlobals $ORG $PEER_TYPE
    
    # Set peer display name (optional, for logs)
    case $ORG in
      1)
          PEER="anchor.client.example.com"
          [ "$PEER_TYPE" = "backup" ] && PEER="backup.client.example.com"
          ;;
      2)
          PEER="anchor.lawfirm.example.com"
          [ "$PEER_TYPE" = "backup" ] && PEER="backup.lawfirm.example.com"
          ;;
      3)
          PEER="anchor.retail.example.com"
          [ "$PEER_TYPE" = "backup" ] && PEER="backup.retail.example.com"
          ;;
    esac

    # Build peer list string (for informational purposes)
    if [ -z "$PEERS" ]; then
      PEERS="$PEER"
    else
      PEERS="$PEERS $PEER"
    fi

    # Add connection parameters
    PEER_CONN_PARMS+=("--peerAddresses $CORE_PEER_ADDRESS")
    PEER_CONN_PARMS+=("--tlsRootCertFiles $CORE_PEER_TLS_ROOTCERT_FILE")
    
    # Shift off the arguments we've processed
    if [ -n "$2" ]; then
      shift 2  # Both ORG and PEER_TYPE were provided
    else
      shift    # Only ORG was provided
    fi
  done
}

verifyResult() {
  if [ $1 -ne 0 ]; then
    fatalln "$2"
  fi
}
