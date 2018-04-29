#!/bin/sh

# NOTE: This is verbose on purpose.

set -e

rm -fr results || true
rm blob* || true

SERVERLOGS=results/servers
CLIENTOUT=results/clients
CHANNELOUT=results/channelbot.console
DUMMYOUT=results/dummy.console

mkdir -p $SERVERLOGS
mkdir -p $CLIENTOUT

echo "STARTING SERVERS..."

for SERVERID in $(seq 5 -1 1)
do
    IDX=$(($SERVERID - 1))
    SERVERCMD="../bin/server -v -i $IDX --config server-$SERVERID.yaml --noratchet"
    if [ $SERVERID -eq 4 ]; then
        sleep 15 # This will force a CDE timeout
    fi
    $SERVERCMD > $SERVERLOGS/server-$SERVERID.console 2>&1 &
    RETVAL=$!
    echo "$SERVERCMD -- $RETVAL"
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

sleep 20 # FIXME: We should not need this, but the servers don't respond quickly
         #        enough on boot right now.

export LASTNODE="localhost:50004"
export NICK1="David"
export NICK2="Jim"
export NICK3="Ben"
export NICK4="Rick"

runclients() {
    echo "Starting clients..."
    CTR=0
    for cid in $(seq 1 4)
    do
        # TODO: Change the recipients to send multiple messages. We can't
        #       run multiple clients with the same user id so we need
        #       updates to make that work.
        #     for nid in 1 2 3 4; do
        for nid in 1
        do
            nid=$((($cid % 4) + 1))
            eval NICK=\${NICK${cid}}
            # Send a channel message
            # CLIENTCMD="timeout 10s ../bin/client -f blob$cid$nid --numnodes 5 -s $LASTNODE -i $cid -d 35 -m \"Channel, $nid\" --nick $NICK"
            # eval $CLIENTCMD >> $CLIENTOUT/client$cid$nid.out 2>&1 &
            # RETVAL=$!
            # eval CLIENTSCH${CTR}=$RETVAL
            # echo "$CLIENTCMD -- $RETVAL"

            # Send a regular message
            CLIENTCMD="timeout 60s ../bin/client -f blob$cid$nid --numnodes 5 -s $LASTNODE -i $cid -d $nid -m \"Hello, $nid\" --nick $NICK --noratchet"
            eval $CLIENTCMD >> $CLIENTOUT/client$cid$nid.out 2>&1 &
            RETVAL=$!
            eval CLIENTS${CTR}=$RETVAL
            echo "$CLIENTCMD -- $RETVAL"
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
../bin/client channelbot -v -i 31 --nick "#general" --numnodes 5 -s $LASTNODE \
              -f blobchannel --noratchet \
              2>&1 > $CHANNELOUT &
echo $! >> results/serverpids

# Start a dummy client
../bin/client -i 35 -d 35 -s $LASTNODE --numnodes 5 -m "dummy" --nick "dummy" \
              --dummyfrequency 0.5 --noratchet \
              -f blobdummy 2>&1 > $DUMMYOUT &
echo $! >> results/serverpids

echo "RUNNING CLIENTS..."
runclients
echo "RUNNING CLIENTS (2nd time)..."
runclients

# HACK HACK HACK: Remove the ratchet warning from client output
for F in $(find results/clients -type f)
do
    cat $F | grep -v "[Rr]atcheting" > $F.tmp
    mv $F.tmp $F
done


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


echo "SUCCESS!"
