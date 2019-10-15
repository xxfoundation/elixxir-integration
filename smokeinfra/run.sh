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
    SERVERCMD="../bin/server -v -i $IDX --roundBufferTimeout 300s --config server-$SERVERID.yaml --noTLS --disablePermissioning"
    $SERVERCMD > $SERVERLOGS/server-$SERVERID.console 2>&1 &
    PIDVAL=$!
    echo "$SERVERCMD -- $PIDVAL"
done

echo "STARTING GATEWAYS..."

# Start gateways
for GWID in $(seq 3 -1 1)
do
    IDX=$(($GWID - 1))
    GATEWAYCMD="../bin/gateway -v -i $IDX --config gateway-$GWID.yaml --noTLS --disablePermissioning"
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
}

trap finish EXIT
trap finish INT

sleep 5

echo "STOPPING SERVERS AND GATEWAYS..."
# NOTE: jobs -p doesn't work in a signal handler
for job in $(cat results/serverpids)
do
    echo "Stopping $job"
    kill $job
done

echo "CHECKING OUTPUT FOR ERRORS"
set +x

cat $SERVERLOGS/server-*.log | grep "ERROR" | grep -v "context" | grep -v "metrics" | grep -v "database" > results/server-errors.txt || true
cat $SERVERLOGS/server-*.log | grep "FATAL" |  grep -v "context" | grep -v "database" >> results/server-errors.txt || true
diff -ruN results/server-errors.txt noerrors.txt

cat $GATEWAYLOGS/*.log | grep "ERROR" | grep -v "certificate" | grep -v "context" | grep -v "database" | grep -v "Failed to read key" | grep -v "$IGNOREMSG" > results/gateway-errors.txt || true
cat $GATEWAYLOGS/*.log | grep "FATAL" | grep -v "context" | grep -v "database" >> results/gateway-errors.txt || true
diff -ruN results/gateway-errors.txt noerrors.txt

echo "NO OUTPUT ERRORS"

echo "CHECKING THAT AT LEAST 2 ROUNDS RAN"
cat results/server-3.log | grep "RID 1 ReceiveFinishRealtime END" > rid.txt || true
if [ ! -s rid.txt ]; then
    echo "FAILURE!"
    exit 42
fi

echo "SUCCESS!"

tail $SERVERLOGS/*.console
