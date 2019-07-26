#!/bin/sh

# NOTE: This is verbose on purpose.

set -e

rm -fr results || true

SERVERLOGS=results/
GATEWAYLOGS=results/

mkdir -p $SERVERLOGS
mkdir -p $GATEWAYLOGS

echo "STARTING SERVERS..."

for SERVERID in $(seq 3 -1 1)
do
    IDX=$(($SERVERID - 1))
    SERVERCMD="../bin/server -v -i $IDX --roundBufferTimeout 300s --config server-$SERVERID.yaml --keyPairOverride dsa.json"
    $SERVERCMD > $SERVERLOGS/server-$SERVERID.console 2>&1 &
    PIDVAL=$!
    echo "$SERVERCMD -- $PIDVAL"
done

sleep 5 # Give servers some time to boot

echo "STARTING GATEWAYS..."

# Start gateways
for GWID in $(seq 3 -1 1)
do
    IDX=$(($GWID - 1))
    GATEWAYCMD="../bin/gateway -v -i $IDX --config gateway-$GWID.yaml"
    $GATEWAYCMD > $GATEWAYLOGS/gateway-$GWID.console 2>&1 &
    PIDVAL=$!
    echo "$GATEWAYCMD -- $PIDVAL"
done

jobs -p > results/serverpids

finish() {
    echo "KILLED! STOPPING SERVERS AND GATEWAYS..."
    # NOTE: jobs -p doesn't work in a signal handler
    for job in $(cat results/serverpids)
    do
        echo "KILLING $job"
        kill $job || true
    done
    tail $SERVERLOGS/*.console
}

trap finish EXIT
trap finish INT

sleep 60

echo "STOPPING SERVERS AND GATEWAYS..."
# NOTE: jobs -p doesn't work in a signal handler
for job in $(cat results/serverpids)
do
    echo "Stopping $job"
    kill $job
done
tail $SERVERLOGS/*.console
