#!/bin/bash

set -e

# --- Define variables to use for the test & local network ---

DEBUGLEVEL=${DEBUGLEVEL-1}
SERVERLOGS=results/servers
GATEWAYLOGS=results/gateways
UDBOUT=results/udb-console.txt

# --- Setup a local network ---

rm -rf results.bak || true
mv results results.bak || rm -rf results || true
rm -rf client*.log blob* rick*.bin ben*.bin
mkdir results

mkdir -p $SERVERLOGS
mkdir -p $GATEWAYLOGS

# Start the network
source network.sh

# This remains commented out while using HTTP
#echo "DOWNLOADING TLS Cert..."
#CMD="openssl s_client -showcerts -connect $(tr -d '[:space:]' <results/startgwserver.txt)"
#echo "$CMD"
#eval "$CMD" </dev/null 2>&1 >"results/startgwcert.bin"
#CMD="cat results/startgwcert.bin | openssl x509 -outform PEM"
#echo "$CMD"
#eval "$CMD" >"results/startgwcert.pem"
#head "results/startgwcert.pem"
#
#echo "DOWNLOADING NDF..."
#CLIENTCMD="../bin/client getndf -v $DEBUGLEVEL --gwhost $(tr -d '[:space:]' <results/startgwserver.txt) --cert results/startgwcert.pem"
#eval "$CLIENTCMD" >>results/ndf.json 2>&1 &
#echo "$CLIENTCMD -- $PIDVAL"
#wait $PIDVAL

while :; do
    sleep 10
done
