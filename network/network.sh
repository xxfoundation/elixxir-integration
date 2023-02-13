# This script is used to start a basic 5 node network for running clients on. It is meant to be `source`'d into a script
# which will run clients on the network, such as `client-session-tests.sh` or the main `run.sh`. 
# 
# You **must** source it, because otherwise the `trap finish EXIT` instruction will cause the network to stop when 
# network.sh returns to your script or shell. Sourcing it will "import" the commands into your script instead, causing 
# the trap instruction to stop the network when your script/shell exits.

echo "STARTING SERVERS..."

SERVERLOGS=results/servers
GATEWAYLOGS=results/gateways
UDBOUT=results/udb-console.txt

# Copy udbContact into place when running locally.
cp udbContact.bin results/udbContact.bin

PERMCMD="../bin/permissioning --logLevel $DEBUGLEVEL -c permissioning.yaml "
$PERMCMD > results/permissioning-console.txt 2>&1 &
PIDVAL=$!
echo "$PERMCMD -- $PIDVAL"


# Run Client Registrar
CLIENT_REG_CMD="../bin/client-registrar \
-l 2 -c client-registrar.yaml"
$CLIENT_REG_CMD > results/client-registrat-console.txt 2>&1 &
PIDVAL=$!
echo "$CLIENT_REG_CMD -- $PIDVAL"

for SERVERID in $(seq 5 -1 1)
do
    IDX=$(($SERVERID - 1))
    SERVERCMD="../bin/server --logLevel $DEBUGLEVEL --config server-$SERVERID.yaml"
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
    GATEWAYCMD="../bin/gateway --logLevel $DEBUGLEVEL --config gateway-$GWID.yaml"
    $GATEWAYCMD > $GATEWAYLOGS/gateway-$GWID-console.txt 2>&1 &
    PIDVAL=$!
    echo "$GATEWAYCMD -- $PIDVAL"
done

jobs -p > results/serverpids

finish() {
    echo "STOPPING SERVERS AND GATEWAYS..."
    if [ -n "$NSYSENABLED" ]
    then
        nsys stop --session=gputest
    fi
    # NOTE: jobs -p doesn't work in a signal handler
    for job in $(cat results/serverpids)
    do
        echo "KILLING $job"
        kill $job || true
    done

    sleep 5

    for job in $(cat results/serverpids)
    do
        echo "KILL -9 $job"
        kill -9 $job || true
    done
    #tail $SERVERLOGS/*
    #tail $CLIENTCLEAN/*
    #diff -aruN clients.goldoutput $CLIENTCLEAN
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
    grep -a "RID 1 ReceiveFinishRealtime END" results/servers/server-* > rid.txt || true
    cnt=$(($cnt + 1))
    echo -n "."
done

# Start a user discovery bot server
echo "STARTING UDB..."
UDBCMD="../bin/udb --logLevel $DEBUGLEVEL --skipVerification --protoUserPath	udbProto.json --config udb.yaml -l 1"
$UDBCMD >> $UDBOUT 2>&1 &
PIDVAL=$!
echo $PIDVAL >> results/serverpids
echo "$UDBCMD -- $PIDVAL"
rm rid.txt || true
while [ ! -s rid.txt ] && [ $cnt -lt 30 ]; do
    sleep 1
    grep -a "Sending Poll message" results/udb-console.txt > rid.txt || true
    cnt=$(($cnt + 1))
    echo -n "."
done

