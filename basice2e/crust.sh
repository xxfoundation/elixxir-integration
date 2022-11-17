#!/bin/bash

# This file contains logic to run clients with the specific goal of putting
# backups testing backups on Crust's architecture. These clients will then
# recover these backups and ensure the recovered file matches the originally
# backed up file.

# NOTE: This is verbose on purpose.
################################################################################
## Initial Set Up & Clean Up of Past Runs
################################################################################

set -e
rm -fr results.bak || true
mv results results.bak || rm -fr results || true
rm *-contact.json || true
rm server-5.qdstrm || true
rm server-5.qdrep || true

mkdir -p .elixxir

if [ $# -gt 1 ]
then
    echo "usage: $0 [gatewayip:port]"
    exit
fi


NETWORKENTRYPOINT=$1

DEBUGLEVEL=${DEBUGLEVEL-1}

SERVERLOGS=results/servers
GATEWAYLOGS=results/gateways
UDBOUT=results/udb-console.txt
CLIENTOUT=results/clients
CLIENTCLEAN=results/clients-cleaned

CLIENTOPTS="--password hello --ndf results/ndf.json --verify-sends --sendDelay 100 --waitTimeout 360 -v $DEBUGLEVEL"
CLIENTUDOPTS="--password hello --ndf results/ndf.json -v $DEBUGLEVEL"
CLIENTALTUDOPTS="--alternateUd --altUdCert crustUd.crt --altUdContactFile crustUdContact.bin --altUdAddress 18.198.117.203:11420"

CLIENTID=320
ACCOUNTNAME=crustIntegrationTest$CLIENTID

mkdir -p $SERVERLOGS
mkdir -p $GATEWAYLOGS
mkdir -p $CLIENTOUT
mkdir -p $CLIENTCLEAN

################################################################################
## Network Set Up
################################################################################

# removeUser will remove the user from the UD
removeUser() {
  CLIENTCMD="timeout 240s ../bin/client ud $CLIENTUDOPTS $CLIENTALTUDOPTS -l $CLIENTOUT/client$CLIENTID.log -s blob$CLIENTID --remove $ACCOUNTNAME"
  eval $CLIENTCMD >> $CLIENTOUT/client$CLIENTID.txt &
  PIDVAL=$!
  echo "$CLIENTCMD -- $PIDVAL"
  wait $PIDVAL

}

#removeUser

# Ensure removeUser is called whenever this script closes, on success or failure
#trap removeUser EXIT
#trap removeUser INT


if [ "$NETWORKENTRYPOINT" == "betanet" ]
then
    NETWORKENTRYPOINT=$(sort -R betanet.txt | head -1)
elif [ "$NETWORKENTRYPOINT" == "mainnet" ]
then
    NETWORKENTRYPOINT=$(sort -R mainnet.txt | head -1)
elif [ "$NETWORKENTRYPOINT" == "release" ]
then
    NETWORKENTRYPOINT=$(sort -R release.txt | head -1)
elif [ "$NETWORKENTRYPOINT" == "devnet" ]
then
    NETWORKENTRYPOINT=$(sort -R devnet.txt | head -1)
elif [ "$NETWORKENTRYPOINT" == "" ]
then
    NETWORKENTRYPOINT=$(head -1 network.config)
fi

echo "NETWORK: $NETWORKENTRYPOINT"

if [ "$NETWORKENTRYPOINT" == "localhost:8440" ]
then
    source network.sh

else
    echo "Connecting to network defined at $NETWORKENTRYPOINT"
    echo $NETWORKENTRYPOINT > results/startgwserver.txt
fi

echo "DOWNLOADING TLS Cert..."
CMD="openssl s_client -showcerts -connect $(tr -d '[:space:]' < results/startgwserver.txt)"
echo $CMD
eval $CMD < /dev/null 2>&1 > "results/startgwcert.bin"
CMD="cat results/startgwcert.bin | openssl x509 -outform PEM"
echo $CMD
eval $CMD > "results/startgwcert.pem"
head "results/startgwcert.pem"

echo "DOWNLOADING NDF..."
CLIENTCMD="../bin/client getndf --gwhost $(tr -d '[:space:]' < results/startgwserver.txt) --cert results/startgwcert.pem"
eval $CLIENTCMD >> results/ndf.json 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

cat results/ndf.json | jq . | head -5

file results/ndf.json

if [ ! -s results/ndf.json ]
then
    echo "results/ndf.json is empty, cannot proceed"
    exit -1
fi


#export GRPC_GO_LOG_VERBOSITY_LEVEL=99
#export GRPC_GO_LOG_SEVERITY_LEVEL=info

###############################################################################
# Test Crust
###############################################################################

echo "TESTING CRUST..."

# Register username with UD
# fixme: must find way to make this replicable in integration testing, possibly have
# fixme: a way to remove this account via CLI
CLIENTCMD="timeout 240s ../bin/client ud $CLIENTUDOPTS $CLIENTALTUDOPTS -l $CLIENTOUT/client$CLIENTID.log -s blob$CLIENTID --register $ACCOUNTNAME"
eval $CLIENTCMD >> $CLIENTOUT/client$CLIENTID.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

# Upload file to Crust
CLIENTCMD="timeout 240s ../bin/client crust $CLIENTUDOPTS $CLIENTALTUDOPTS -l $CLIENTOUT/client$CLIENTID.log -s blob$CLIENTID --upload --file LoremIpsum.txt"
eval $CLIENTCMD >> $CLIENTOUT/client$CLIENTID.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

# Recover file from Crust
CLIENTCMD="timeout 240s ../bin/client crust $CLIENTUDOPTS $CLIENTALTUDOPTS -l $CLIENTOUT/client$CLIENTID.log -s blob$CLIENTID --recover --file LoremIpsum.txt"
eval $CLIENTCMD >> $CLIENTOUT/client$CLIENTID.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

###############################################################################
# Close Local Network
###############################################################################

if [ "$NETWORKENTRYPOINT" == "localhost:8440" ]
then
    cat $SERVERLOGS/server-*.log | grep -a "ERROR" | grep -a -v "context" | grep -av "metrics" | grep -av "database" | grep -av RequestClientKey > results/server-errors.txt || true
    cat $SERVERLOGS/server-*.log | grep -a "FATAL" | grep -a -v "context" | grep -av "transport is closing" | grep -av "database" >> results/server-errors.txt || true
    diff -aruN results/server-errors.txt noerrors.txt
    IGNOREMSG="GetRoundBufferInfo: Error received: rpc error: code = Unknown desc = round buffer is empty"
    cat $GATEWAYLOGS/*.log | grep -a "ERROR" | grep -av "context" | grep -av "certificate" | grep -av "Failed to read key" | grep -av "$IGNOREMSG" > results/gateway-errors.txt || true
    cat $GATEWAYLOGS/*.log | grep -a "FATAL" | grep -av "context" | grep -av "transport is closing" >> results/gateway-errors.txt || true
    diff -aruN results/gateway-errors.txt noerrors.txt
fi