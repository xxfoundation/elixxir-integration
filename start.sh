#!/bin/bash

mkdir -p .elixxir
mkdir -p blobs
mkdir -p results

DEBUGLEVEL=${DEBUGLEVEL-1}

if [ -f results/network/serverpids ]
then
  echo "SERVERS ALREADY UP..."
else
  source network/network.sh results bin
fi

if [ -f results/ndf.json ]
then
  echo "NDF FOUND..."
else
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
fi

if [ ! -z $1 ]
then
  TEST=$1
  /bin/bash tests/$TEST/run.sh results/$TEST tests/$TEST/clients.goldoutput results/ndf.json || true
fi
