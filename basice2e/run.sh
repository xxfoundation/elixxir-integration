#!/bin/sh

# NOTE: This is verbose on purpose.

set -e

rm -fr results || true
rm blob* || true

SERVERLOGS=results/servers
GATEWAYLOGS=results/gateways
CLIENTOUT=results/clients
CHANNELOUT=results/channelbot.console
DUMMYOUT=results/dummy.console
UDBOUT=results/udb.console

mkdir -p $SERVERLOGS
mkdir -p $GATEWAYLOGS
mkdir -p $CLIENTOUT

echo "STARTING SERVERS..."

for SERVERID in $(seq 5 -1 1)
do
    IDX=$(($SERVERID - 1))
    SERVERCMD="../bin/server -v -i $IDX --config server-$SERVERID.yaml"
    if [ $SERVERID -eq 4 ]; then
        sleep 15 # This will force a CDE timeout
    fi
    $SERVERCMD > $SERVERLOGS/server-$SERVERID.console 2>&1 &
    PIDVAL=$!
    echo "$SERVERCMD -- $PIDVAL"
done

jobs -p > results/serverpids

finish() {
    echo "STOPPING SERVERS..."
    # NOTE: jobs -p doesn't work in a signal handler
    for job in $(cat results/serverpids)
    do
        echo "KILLING $job"
        kill $job || true
    done
    tail $SERVERLOGS/*
    tail $CLIENTOUT/*
    diff -ruN clients.goldoutput $CLIENTOUT
}

trap finish EXIT
trap finish INT

sleep 45 # FIXME: We should not need this, but the servers don't respond quickly
         #        enough on boot right now.

export GATEWAY="localhost:8444,localhost:8443,localhost:8442,localhost:8441,localhost:8440"
runclients() {
    echo "Starting clients..."
    CTR=0

    for cid in $(seq 4 7)
    do
        # TODO: Change the recipients to send multiple messages. We can't
        #       run multiple clients with the same user id so we need
        #       updates to make that work.
        #     for nid in 1 2 3 4; do

        for nid in 1
        do
            nid=$(((($cid + 1) % 4) + 4))
            eval NICK=\${NICK${cid}}
            # Send a regular message
            CLIENTCMD="timeout 80s ../bin/client -f blob$cid -g $GATEWAY -c ../keys/gateway.cmix.rip.crt -i $cid -d $nid -m \"Hello, $nid\""
            eval $CLIENTCMD >> $CLIENTOUT/client$cid$nid.out 2>&1 &
            PIDVAL=$!
            eval CLIENTS${CTR}=$PIDVAL
            echo "$CLIENTCMD -- $PIDVAL"
            CTR=$(($CTR + 1))
        done
    done

    echo "WAITING FOR $CTR CLIENTS TO EXIT..."
    for i in $(seq 0 $(($CTR - 1)))
    do
        eval echo "Waiting on \${CLIENTS${i}} ..."
        eval wait \${CLIENTS${i}}
    done
}

# Start a channelbot server
CHANNELCMD="../bin/channelbot -v -i 31 -c ..//keys/gateway.cmix.rip.crt -g $GATEWAY -f blobchannel"
$CHANNELCMD >> $CHANNELOUT 2>&1 &
PIDVAL=$!
echo $PIDVAL >> results/serverpids
echo "$CHANNELCMD -- $PIDVAL"

# Start a user discovery bot server
UDBCMD="../bin/udb -v --config udb.yaml"
$UDBCMD >> $UDBOUT 2>&1 &
PIDVAL=$!
echo $PIDVAL >> results/serverpids
echo "$UDBCMD -- $PIDVAL"

# Start a dummy client
DUMMYCMD="../bin/client -i 35 -d 35 -g $GATEWAY -m \"dummy\" --dummyfrequency 2 -c ../keys/gateway.cmix.rip.crt -f blobdummy"
$DUMMYCMD >> $DUMMYOUT 2>&1 &
PIDVAL=$!
echo $PIDVAL >> results/serverpids
echo "$DUMMYCMD -- $PIDVAL"

# Start gateways
for GWID in $(seq 5 -1 1)
do
    GATEWAYCMD="../bin/gateway -v --config gateway-$GWID.yaml"
    $GATEWAYCMD > $GATEWAYLOGS/gateway-$GWID.console 2>&1 &
    PIDVAL=$!
    echo $PIDVAL >> results/serverpids
    echo "$GATEWAYCMD -- $PIDVAL"
done

# Register two users and then do UDB search on each other
CLIENTCMD="timeout 90s ../bin/client -f blob9 -g $GATEWAY -E "jake@elixxir.io" -i 9 -d 3 -c ../keys/gateway.cmix.rip.crt"
eval $CLIENTCMD >> $CLIENTOUT/client9.out 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

CLIENTCMD="timeout 90s ../bin/client -f blob18 -g $GATEWAY -E "bernardo@elixxir.io" -i 18 -d 3 -c ../keys/gateway.cmix.rip.crt -m \"SEARCH EMAIL jake@elixxir.io\""
eval $CLIENTCMD >> $CLIENTOUT/client18.out 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

CLIENTCMD="timeout 90s ../bin/client -f blob9 -g $GATEWAY -i 9 -d 3 -c ../keys/gateway.cmix.rip.crt -m \"SEARCH EMAIL bernardo@elixxir.io\""
eval $CLIENTCMD >> $CLIENTOUT/client9.out 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

# Send a channel message that all clients will receive
CLIENTCMD="timeout 60s ../bin/client -f blob8 -c ../keys/gateway.cmix.rip.crt -g $GATEWAY -i 8 -d 31 -m \"Channel, Hello\""
eval $CLIENTCMD >> $CLIENTOUT/client8.out 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

sleep 10 # Spend some time waiting for the channel bot to send messages

echo "RUNNING CLIENTS..."
runclients
echo "RUNNING CLIENTS (2nd time)..."
runclients

diff -ruN clients.goldoutput $CLIENTOUT
cat $SERVERLOGS/*.log | grep "ERROR" > results/server-errors.txt || true
cat $SERVERLOGS/*.log | grep "FATAL" >> results/server-errors.txt || true
diff -ruN results/server-errors.txt noerrors.txt
cat $CHANNELOUT | grep "ERROR" > results/channel-errors.txt || true
cat $CHANNELOUT | grep "FATAL" >> results/channel-errors.txt || true
diff -ruN results/channel-errors.txt noerrors.txt
cat $DUMMYOUT | grep "ERROR" > results/dummy-errors.txt || true
cat $DUMMYOUT | grep "FATAL" >> results/dummy-errors.txt || true
diff -ruN results/dummy-errors.txt noerrors.txt
IGNOREMSG="GetRoundBufferInfo: Error received: rpc error: code = Unknown desc = round buffer is empty"
cat $GATEWAYLOGS/*.log | grep "ERROR" | grep -v $IGNOREMSG > results/gateway-errors.txt || true
cat $GATEWAYLOGS/*.log | grep "FATAL" >> results/gateway-errors.txt || true
diff -ruN results/gateway-errors.txt noerrors.txt



echo "SUCCESS!"
