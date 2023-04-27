# This script is used to start a basic 5 node network for running clients on. It is meant to be `source`'d into a script
# which will run clients on the network, such as `client-session-tests.sh` or the main `run.sh`. 
# 
# You **must** source it, because otherwise the `trap finish EXIT` instruction will cause the network to stop when 
# network.sh returns to your script or shell. Sourcing it will "import" the commands into your script instead, causing 
# the trap instruction to stop the network when your script/shell exits.

set -e
mkdir -p .elixxir

if [ $# -gt 2 ]
then
    echo "usage: $0 results_dir bin_dir"
    exit
fi

# NOTE these must have different names for each package
NETRESULTS=$1
NETBIN=$2

echo "STARTING SERVERS..."

SERVERLOGS=$NETRESULTS/servers
GATEWAYLOGS=$NETRESULTS/gateways
UDBOUT=$NETRESULTS/udb-console.txt

mkdir -p $SERVERLOGS
mkdir -p $GATEWAYLOGS

PERMCMD="$NETBIN/permissioning --logLevel $DEBUGLEVEL -c network/permissioning.yaml "
$PERMCMD > $NETRESULTS/permissioning-console.txt 2>&1 &
PIDVAL=$!
echo "$PERMCMD -- $PIDVAL"


# Run Client Registrar
CLIENT_REG_CMD="$NETBIN/client-registrar \
-l 2 -c network/client-registrar.yaml"
$CLIENT_REG_CMD > $NETRESULTS/client-registrat-console.txt 2>&1 &
PIDVAL=$!
echo "$CLIENT_REG_CMD -- $PIDVAL"

for SERVERID in $(seq 5 -1 1)
do
    IDX=$(($SERVERID - 1))
    SERVERCMD="$NETBIN/server --logLevel $DEBUGLEVEL --config network/server-$SERVERID.yaml"
    if [ $SERVERID -eq 5 ] && [ -n "$NSYSENABLED" ]
    then
        SERVERCMD="nsys profile --session-new=gputest --trace=cuda -o server-$SERVERID $SERVERCMD"
    fi
    $SERVERCMD > $SERVERLOGS/server-$SERVERID-console.txt 2>&1 &
    PIDVAL=$!
    echo "$SERVERCMD -- $PIDVAL"
done

# Start gateways
for GWID in $(seq 5 -1 1)
do
    IDX=$(($GWID - 1))
    GATEWAYCMD="$NETBIN/gateway --logLevel $DEBUGLEVEL --config network/gateway-$GWID.yaml"
    $GATEWAYCMD > $GATEWAYLOGS/gateway-$GWID-console.txt 2>&1 &
    PIDVAL=$!
    echo "$GATEWAYCMD -- $PIDVAL"
done

jobs -p > $NETRESULTS/serverpids

finish() {
    echo "STOPPING SERVERS AND GATEWAYS..."
    if [ -n "$NSYSENABLED" ]
    then
        nsys stop --session=gputest
    fi
    # NOTE: jobs -p doesn't work in a signal handler
    for job in $(cat $NETRESULTS/serverpids)
    do
        echo "KILLING $job"
        kill $job || true
    done

    sleep 5

    for job in $(cat $NETRESULTS/serverpids)
    do
        echo "KILL -9 $job"
        kill -9 $job || true
    done
    #tail $SERVERLOGS/*
    #tail $CLIENTCLEAN/*
    #diff -aruN clients.goldoutput $CLIENTCLEAN

    #cat $CLIENTOUT/* | strings | grep -ae "ERROR" -e "FATAL" > results/client-errors || true
    #diff -ruN results/client-errors.txt noerrors.txt
    cat $SERVERLOGS/server-*.log | grep -a "ERROR" | grep -a -v "context" | grep -av "metrics" | grep -av "database" | grep -av RequestClientKey > $NETRESULTS/server-errors.txt || true
    cat $SERVERLOGS/server-*.log | grep -a "FATAL" | grep -a -v "context" | grep -av "transport is closing" | grep -av "database" >> $NETRESULTS/server-errors.txt || true
    diff -aruN $NETRESULTS/server-errors.txt noerrors.txt
    IGNOREMSG="GetRoundBufferInfo: Error received: rpc error: code = Unknown desc = round buffer is empty"
    IGNORESERVE="Failed to serve "
    IGNORESTART="Failed to start "
    IGNOREREG="WARNING: MINIMUM REGISTERED NODES HAS BEEN CHANGED"
    cat $GATEWAYLOGS/*.log | grep -a "ERROR" | grep -av "context" | grep -av "certificate" | grep -av "Failed to read key" | grep -av "$IGNOREMSG" | grep -av "$IGNORESERVE" | grep -av "$IGNORESTART" | grep -av "$IGNOREREG" > results/gateway-errors.txt || true
    cat $GATEWAYLOGS/*.log | grep -a "FATAL" | grep -av "context" | grep -av "transport is closing" >> results/gateway-errors.txt || true
    diff -aruN results/gateway-errors.txt noerrors.txt
    echo "Checking backup files for equality..."
    # diff -aruN $CLIENTOUT/client120A.backup.json $CLIENTOUT/client120B.backup.json > client120BackupDiff.txt
    #diff -aruN $CLIENTOUT/client121A.backup.json $CLIENTOUT/client121B.backup.json > client121BackupDiff.txt || true
    # diff -aruN  client120BackupDiff.txt noerrors.txt
    #echo "NOTE: BACKUP CHECK DISABLED, this should be uncommented when turned back on!"
    #diff -aruN  client121BackupDiff.txt noerrors.txt
}

trap finish EXIT
trap finish INT

# Sleeps can die in a fire on the sun, we wait for the servers to start running
# rounds
rm rid.txt || true
touch rid.txt
cnt=0
echo -n "Waiting for a round to run"
while [ ! -s rid.txt ] && [ $cnt -lt 120 ]; do
    sleep 1
    grep -a "RID 1 ReceiveFinishRealtime END" $NETRESULTS/servers/server-* > rid.txt || true
    cnt=$(($cnt + 1))
    echo -n "."
done

# Start a user discovery bot server
echo "STARTING UDB..."
UDBCMD="$NETBIN/udb --logLevel $DEBUGLEVEL --skipVerification --protoUserPath	network/udbProto.json --config network/udb.yaml -l 1"
$UDBCMD >> $UDBOUT 2>&1 &
PIDVAL=$!
echo $PIDVAL >> $NETRESULTS/serverpids
echo "$UDBCMD -- $PIDVAL"
rm rid.txt || true
while [ ! -s rid.txt ] && [ $cnt -lt 30 ]; do
    sleep 1
    grep -a "Sending Poll message" $NETRESULTS/udb-console.txt > rid.txt || true
    cnt=$(($cnt + 1))
    echo -n "."
done

