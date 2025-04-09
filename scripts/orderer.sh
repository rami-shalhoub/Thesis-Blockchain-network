#!/bin/bash


CHANNEL_NAME=$1


export PATH=${PWD}/../bin:$PATH
export ORDERER_ADMIN_TLS_SIGN_CERT=${PWD}/orgCrypto/ordererOrganizations/example.com/orderers/orderer.example.com/tls/server.crt 
export ORDERER_ADMIN_TLS_PRIVATE_KEY=${PWD}/orgCrypto/ordererOrganizations/example.com/orderers/orderer.example.com/tls/server.key


#+ Create the Channel
# osnadmin channel join --channelID ${CHANNEL_NAME} --config-block ./channel-artifacts/${CHANNEL_NAME}.tx -o localhost:6001 --ca-file "$ORDERER_CA" --client-cert "$ORDERER_ADMIN_TLS_SIGN_CERT" --client-key "$ORDERER_ADMIN_TLS_PRIVATE_KEY" >> log.txt 2>&1
# osnadmin channel join --channelID ${CHANNEL_NAME} --config-block ./channel-artifacts/genesis.block -o localhost:6001 --ca-file "$ORDERER_CA" --client-cert "$ORDERER_ADMIN_TLS_SIGN_CERT" --client-key "$ORDERER_ADMIN_TLS_PRIVATE_KEY" >> log.txt 2>&1
osnadmin channel join \
    --channelID ${CHANNEL_NAME} \
    --config-block ./channel-artifacts/${CHANNEL_NAME}.block \
    -o 0.0.0.0:6001 \
    --ca-file "$ORDERER_CA" \
    --client-cert "$ORDERER_ADMIN_TLS_SIGN_CERT" \
    --client-key "$ORDERER_ADMIN_TLS_PRIVATE_KEY" >> log.txt 2>&1
#+ Check is the Channel is created
osnadmin channel list -o orderer.example.com:6001 --ca-file "$ORDERER_CA" --client-cert "$ORDERER_ADMIN_TLS_SIGN_CERT" --client-key "$ORDERER_ADMIN_TLS_PRIVATE_KEY"