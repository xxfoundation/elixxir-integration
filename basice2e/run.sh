#!/bin/sh

# NOTE: This is verbose on purpose.

set -e

SERVERLOGS=results/servers
CLIENTOUT=results/clients

mkdir -p $SERVERLOGS
mkdir -p $CLIENTOUT

echo "STARTING SERVERS..."

for SERVERID in $(seq 1 5)
do
    IDX=$(($SERVERID - 1))
    SERVERCMD="../bin/server -v -i $IDX --config server-$SERVERID.yaml"
    eval $SERVERCMD > $SERVERLOGS/server-$SERVERID.console 2>&1 &
    echo "$SERVERCMD -- $!"
done

finish() {
    echo "STOPPING SERVERS..."
    for job in $(jobs -p)
    do
        kill $job || true
    done
    tail results/*
}

trap finish EXIT
trap finish INT

sleep 10 # FIXME: We should not need this, but the servers don't respond quickly
         #        enough on boot right now.

LASTNODE="localhost:50004"


echo "STARTING CLIENTS..."
CTR=0

for cid in 1 2 3 4; do
    # TODO: Change the recipients to send multiple messages. We can't
    #       run multiple clients with the same user id so we need
    #       updates to make that work.
    #     for nid in 1 2 3 4; do
    for nid in 1; do
        nid=$((($cid % 4) + 1))
        ../bin/client --numnodes 5 -s $LASTNODE -i $cid -d $nid -m "Hello, $nid" > results/client$cid$nid.out 2>&1 &
        RETVAL=$!
        echo "../bin/client --numnodes 5 -s $LASTNODE -i $cid -d $nid -m \"Hello, $nid\" -- $RETVAL"
        eval CLIENTS${CTR}=$RETVAL
        CTR=$(($CTR + 1))
    done
done

echo "WAITING FOR $CTR CLIENTS TO EXIT..."
for i in $(seq 0 $(($CTR - 1))); do
    eval echo "Waiting on \${CLIENTS${i}} ..."
    eval wait \${CLIENTS${i}}
done

diff -ruN 
