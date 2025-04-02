#!/usr/bin/env bash

function one_line_pem {
    echo "`awk 'NF {sub(/\\n/, ""); printf "%s\\\\\\\n",$0;}' $1`"
}

function json_ccp {
    local PP=$(one_line_pem $5)
    local CP=$(one_line_pem $6)
    sed -e "s/\${ORG}/$1/" \
        -e "s/\${anchorPORT}/$2/" \
        -e "s/\${backupPORT}/$3/" \
        -e "s/\${CAPORT}/$4/" \
        -e "s#\${PEERPEM}#$PP#" \
        -e "s#\${CAPEM}#$CP#" \
        organizations/ccp-template.json
}

function yaml_ccp {
    local PP=$(one_line_pem $5)
    local CP=$(one_line_pem $6)
    sed -e "s/\${ORG}/$1/" \
        -e "s/\${anchorPORT}/$2/" \
        -e "s/\${backupPORT}/$3/" \
        -e "s/\${CAPORT}/$4/" \
        -e "s#\${PEERPEM}#$PP#" \
        -e "s#\${CAPEM}#$CP#" \
        organizations/ccp-template.yaml | sed -e $'s/\\\\n/\\\n          /g'
}

ORG=client
anchorPORT=7000
backupPORT=7010
CAPORT=7020
PEERPEM=orgCrypto/peerOrganizations/client.example.com/tlsca/tlsca.client.example.com-cert.pem
CAPEM=orgCrypto/peerOrganizations/client.example.com/ca/ca.client.example.com-cert.pem

echo "$(json_ccp $ORG $P0PORT $CAPORT $PEERPEM $CAPEM)" > orgCrypto/peerOrganizations/client.example.com/connection-clientOrg.json
echo "$(yaml_ccp $ORG $P0PORT $CAPORT $PEERPEM $CAPEM)" > orgCrypto  /peerOrganizations/client.example.com/connection-clientOrg.yaml

ORG=lawfirm
anchorPORT=8000
backupPORT=8010
CAPORT=8020
PEERPEM=orgCrypto/peerOrganizations/lawfirm.example.com/tlsca/tlsca.lawfirm.example.com-cert.pem
CAPEM=orgCrypto/peerOrganizations/lawfirm.example.com/ca/ca.lawfirm.example.com-cert.pem

echo "$(json_ccp $ORG $P0PORT $CAPORT $PEERPEM $CAPEM)" > orgCrypto/peerOrganizations/lawfirm.example.com/connection-lawfirmOrg.json
echo "$(yaml_ccp $ORG $P0PORT $CAPORT $PEERPEM $CAPEM)" > orgCrypto/peerOrganizations/lawfirm.example.com/connection-lawfirmOrg.yaml

ORG=retail
anchorPORT=9000
backupPORT=9010
CAPORT=9020
PEERPEM=orgCrypto/peerOrganizations/retial.example.com/tlsca/tlsca.retial.example.com-cert.pem
CAPEM=orgCrypto/peerOrganizations/retial.example.com/ca/ca.retial.example.com-cert.pem

echo "$(json_ccp $ORG $P0PORT $CAPORT $PEERPEM $CAPEM)" > orgCrypto/peerOrganizations/retial.example.com/connection-retailOrg.json
echo "$(yaml_ccp $ORG $P0PORT $CAPORT $PEERPEM $CAPEM)" > orgCrypto/peerOrganizations/retial.example.com/connection-retailOrg.yaml
