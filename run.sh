#!/bin/bash

set -e


while [ $# -gt 1 ]; do
    if [[ $1 == "--"* ]]; then
        v="${1/--/}"
        declare "$v"="$2"
        shift
    fi
    shift
done

if [ $# -gt 1 ]
then
    echo "usage: $0 [gatewayip:port]"
    exit
fi

NETWORKENTRYPOINT=$1

DEBUGLEVEL=${DEBUGLEVEL-1}

rm -fr blobs || true
rm -fr results.bak || true
mv results results.bak || rm -fr results || true
mkdir -p .elixxir
mkdir -p blobs
mkdir -p results

################################################################################
## Network Set Up
################################################################################

if [ "$NETWORKENTRYPOINT" == "betanet" ]
then
    NETWORKENTRYPOINT=$(sort -R network/betanet.txt | head -1)
elif [ "$NETWORKENTRYPOINT" == "mainnet" ]
then
    NETWORKENTRYPOINT=$(sort -R network/mainnet.txt | head -1)
elif [ "$NETWORKENTRYPOINT" == "release" ]
then
    NETWORKENTRYPOINT=$(sort -R network/release.txt | head -1)
elif [ "$NETWORKENTRYPOINT" == "devnet" ]
then
    NETWORKENTRYPOINT=$(sort -R network/devnet.txt | head -1)
elif [ "$NETWORKENTRYPOINT" == "" ]
then
    NETWORKENTRYPOINT=$(head -1 network/network.config)
fi

echo "NETWORK: $NETWORKENTRYPOINT"

if [ "$NETWORKENTRYPOINT" == "localhost:1060" ]
then
    source network/network.sh results bin
    source network/cleanup.sh results

    donefunc() {
      finish
      exit $rc
    }
    trap donefunc EXIT
    trap donefunc INT
else
    echo "Connecting to network defined at $NETWORKENTRYPOINT"
    echo $NETWORKENTRYPOINT > results/startgwserver.txt
fi

echo "DONE LETS DO STUFF"

echo "DOWNLOADING TLS Cert..."
# -alpn h2 added to mimic grpc headers
CMD="openssl s_client -alpn h2 -showcerts -connect $(tr -d '[:space:]' < results/startgwserver.txt)"
echo $CMD
eval $CMD < /dev/null 2>&1 > "results/startgwcert.bin"
CMD="cat results/startgwcert.bin | openssl x509 -outform PEM"
echo $CMD
eval $CMD > "results/startgwcert.pem"
head "results/startgwcert.pem"

echo "DOWNLOADING NDF..."
CLIENTCMD="bin/client getndf --gwhost $(tr -d '[:space:]' < results/startgwserver.txt) --cert results/startgwcert.pem"
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

################################################################################
## Run tests
################################################################################



if [ -z $run ]
then
  TESTS=("basice2e" "dm" "historical" "channels" "fileTransfer" "connect" "broadcast" "groupChat" "ephemeralRegistration" "singleUse" "channelsFileTransfer")
  LOCALTESTS=("basice2e_local" "ud")
else
  TESTS=(${run//,/ })
fi

set +e

if [ "$NETWORKENTRYPOINT" == "localhost:1060" ]
then
    for i in ${LOCALTESTS[@]} ; do
      /bin/bash tests/$i/run.sh results/$i tests/$i/clients.goldoutput results/ndf.json
    done
fi

if [ ${#TESTS[@]} -eq 1 ]
then
  /bin/bash tests/${TESTS[0]}/run.sh results/${TESTS[0]} tests/${TESTS[0]}/clients.goldoutput results/ndf.json
  rc=$?
else
  errs=0
  for i in ${TESTS[@]} ; do
    /bin/bash tests/$i/run.sh results/$i tests/$i/clients.goldoutput results/ndf.json
    errs=$(($errs+$?))
  done
  if [ $errs -gt 1 ]
  then
    rc=1
  fi
fi


# View result logs
# Not using $EDITOR or $VISUAL because many editors that people set those to
# don't have as easy support for viewing multiple files
${INTEGRATION_EDITOR:-gedit} ./basice2e/results/clients/*.out ./basice2e/results/servers/*.console ./basice2e/results/*.log ./basice2e/results/*.console&
