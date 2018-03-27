#!/bin/sh

# NOTE: This is verbose on purpose.

set -e

rm -fr results || true
rm blob* || true

SERVERLOGS=results/servers
CLIENTOUT=results/clients

mkdir -p $SERVERLOGS
mkdir -p $CLIENTOUT

echo "STARTING SERVERS..."

for SERVERID in $(seq 1 5)
do
    IDX=$(($SERVERID - 1))
    SERVERCMD="../bin/server -v -i $IDX --config server-$SERVERID.yaml"
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

LASTNODE="localhost:50004"
NICK1="David"
NICK2="Jim"
NICK3="Ben"
NICK4="Rick"

echo "STARTING CLIENTS..."
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
        eval export NICK=$NICK${cid}
        eval echo ${NICK${cid}}
        CLIENTCMD="../bin/client -f blob$cid$nid --numnodes 5 -s $LASTNODE -i $cid -d $nid -m \"Hello, $nid\" --nick $NICK"
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
        eval NICK=$(echo $NICK${cid})
        CLIENTCMD="../bin/client -f blob$cid$nid --numnodes 5 -s $LASTNODE -i $cid -d $nid -m \"Hello, $nid\" --nick $NICK"
        eval $CLIENTCMD >> $CLIENTOUT/client$cid$nid.out 2>&1 &
        RETVAL=$!
        eval CLIENTS${CTR}=$RETVAL
        echo "$CLIENTCMD -- $RETVAL"
        CTR=$(($CTR + 1))
    done
done

echo "WAITING FOR $CTR CLIENTS (2nd msg set) TO EXIT..."
for i in $(seq 0 $(($CTR - 1)))
do
    eval echo "Waiting on \${CLIENTS${i}} ..."
    eval wait \${CLIENTS${i}}
done


diff -ruN clients.goldoutput $CLIENTOUT

echo "SUCCESS!"
