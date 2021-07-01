#!/bin/sh

# NOTE: This is verbose on purpose.

set -e

rm -fr results || true

SERVERLOGS=results/
GATEWAYLOGS=results/

mkdir -p $SERVERLOGS
mkdir -p $GATEWAYLOGS

PERMCMD="../bin/permissioning -c permissioning.yaml"
$PERMCMD > $SERVERLOGS/permissioning.log 2>&1 &
PIDVAL=$!
echo "$PERMCMD -- $PIDVAL"

echo "STARTING SERVERS..."
PID_SERVER_KILLED=$!
for SERVERID in $(seq 3 -1 1)
do
    IDX=$(($SERVERID - 1))
    SERVERCMD="../bin/server --logLevel 2 --config server-$SERVERID.yaml"
    $SERVERCMD > $SERVERLOGS/server-$SERVERID.console 2>&1 &
    PIDVAL=$!
    echo "$SERVERCMD -- $PIDVAL"
    if [ $SERVERID -eq 1 ]; then
      PID_SERVER_KILLED=$PIDVAL
    fi
    if [ $SERVERID -eq 2 ]; then
        sleep 10 # This will force a CDE timeout
    fi
done

echo "STARTING GATEWAYS..."

# Start gateways
for GWID in $(seq 3 -1 1)
do
    IDX=$(($GWID - 1))
    GATEWAYCMD="../bin/gateway --config gateway-$GWID.yaml"
    $GATEWAYCMD > $GATEWAYLOGS/gateway-$GWID.console 2>&1 &
    PIDVAL=$!
    echo "$GATEWAYCMD -- $PIDVAL"
done

jobs -p > results/serverpids

finish() {
    echo "STOPPING SERVERS AND GATEWAYS..."
    # NOTE: jobs -p doesn't work in a signal handler
    for job in $(cat results/serverpids)
    do
        echo "KILLING $job"
        kill $job || true
    done
}

trap finish EXIT
trap finish INT

# Sleeps can die in a fire on the sun, we wait for the servers to run 2 rounds
rm rid.txt || touch rid.txt
cnt=0
echo -n "Waiting for 2 rounds to run"
while [ ! -s rid.txt ] && [ $cnt -lt 240 ]; do
    sleep 1
    cat results/server-3.log | grep "RID 1 ReceiveFinishRealtime END" > rid.txt || true
    cnt=$(($cnt + 1))
    echo -n "."
done

# Kill the last server
echo "KILLING SERVER 0"
echo $PID_SERVER_KILLED
kill -2 $PID_SERVER_KILLED
# Wait for node to handle kill signal
sleep 30

echo "CHECKING OUTPUT FOR ERRORS"
set +x

cat $SERVERLOGS/server-*.log | grep "ERROR" | grep -v "Poll error" | grep -v "RoundTripPing" | grep -v "context" | grep -v "metrics" | grep -v "database" > results/server-errors.txt || true
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

echo "CHECKING THAT SERVER 0 WAS KILLED PROPERLY"
cat $SERVERLOGS/server-0.log | grep "Round completed, closing!" > serverClose.txt || true
if [ -s serverClose.txt  ]; then
    echo "SERVER 0 CLOSED SUCCESSFULLY"
else
    echo "SERVER 0 WAS NOT CLOSED PROPERLY"
    exit 42
fi

tail $SERVERLOGS/*.console
echo "SUCCESS!"
