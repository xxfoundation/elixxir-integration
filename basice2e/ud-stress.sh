#!/bin/bash

set -e

NETWORKENTRYPOINT=$1

DEBUGLEVEL=${DEBUGLEVEL-1}

RESULTSFOLDER="udresults"
CLIENTOPTS="--password hello --ndf results/ndf.json --verify-sends --sendDelay 100 --waitTimeout 360 --unsafe-channel-creation -v $DEBUGLEVEL"
CLIENTUDOPTS="--password hello --ndf results/ndf.json -v $DEBUGLEVEL"
CLIENTOUT=$RESULTSFOLDER

rm -fr "$RESULTSFOLDER.bak" || true
cp -ra "$RESULTSFOLDER" "$RESULTSFOLDER.bak" || true
mkdir -p "$RESULTSFOLDER" || true

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
    echo "NO NETWORK SPECIFIED, USING mainnet"
    NETWORKENTRYPOINT=$(sort -R mainnet.txt | head -1)
fi

echo "NETWORK: $NETWORKENTRYPOINT"

echo "Connecting to network defined at $NETWORKENTRYPOINT"
echo $NETWORKENTRYPOINT > "$RESULTSFOLDER/startgwserver.txt"

echo "DOWNLOADING TLS Cert..."
CMD="openssl s_client -showcerts -connect $(cat $RESULTSFOLDER/startgwserver.txt)"
echo $CMD
eval $CMD < /dev/null 2>&1 > "$RESULTSFOLDER/startgwcert.bin"
CMD="cat $RESULTSFOLDER/startgwcert.bin | openssl x509 -outform PEM"
echo $CMD
eval $CMD > "$RESULTSFOLDER/startgwcert.pem"
head "$RESULTSFOLDER/startgwcert.pem"

echo "DOWNLOADING NDF..."
CLIENTCMD="../bin/client getndf --gwhost $(cat $RESULTSFOLDER/startgwserver.txt) --cert $RESULTSFOLDER/startgwcert.pem"
eval $CLIENTCMD >> $RESULTSFOLDER/ndf.json 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

cat $RESULTSFOLDER/ndf.json | jq . | head -5

file $RESULTSFOLDER/ndf.json

if [ ! -s $RESULTSFOLDER/ndf.json ]
then
    echo "$RESULTSFOLDER/ndf.json is empty, cannot proceed"
    exit -1
fi

# Create session
if [ ! -s $RESULTSFOLDER/blob13 ]; then
    echo "CREATING NEW CLIENT..."
    CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client13.log -s $CLIENTOUT/blob13 --writeContact $CLIENTOUT/client13-contact.bin --unsafe -m \"Hello from Client13 to myself, without E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client13.txt &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    wait $PIDVAL
    echo "DONE!"
else
    echo "REUSING EXISTING CLIENT..."
    mv $RESULTSFOLDER/client13.txt $RESULTSFOLDER/client13.txt.bak
    mv $RESULTSFOLDER/client13.log $RESULTSFOLDER/client13.log.bak
    CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client13.log -s $CLIENTOUT/blob13 --writeContact $CLIENTOUT/client13-contact.bin --unsafe -m \"Hello from Client13 to myself, without E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client13.txt &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    wait $PIDVAL
    echo "DONE!"
fi

# The following attempts to register a username, not normally needed to be tested...
# CLIENTCMD="timeout 240s ../bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client13.log -s $CLIENTOUT/blob13 --register josh13"
# eval $CLIENTCMD >> $CLIENTOUT/client13.txt &
# PIDVAL=$!
# echo "$CLIENTCMD -- $PIDVAL"
# wait $PIDVAL


# Test forever
while [ true ]; do
    echo "SEARCHING..."
    CLIENTCMD="time timeout 240s ../bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client13.log -s $CLIENTOUT/blob13 --searchusername Jake"
    eval $CLIENTCMD > $CLIENTOUT/josh31.bin &
    PIDVAL1=$!
    echo "$CLIENTCMD -- $PIDVAL1"
    wait $PIDVAL1
    echo "SUCCESS!"
done
