#!/bin/sh

# NOTE: This is verbose on purpose.

set -e

mkdir -p results

echo "STARTING SERVERS..."

../bin/server -v -i 0 --config server-1.yaml > results/server-1.console 2>&1 &
SERVER1=$!
echo "../bin/server -v -i 0 --config server-1.yaml -- $SERVER1"

../bin/server -v -i 1 --config server-2.yaml > results/server-2.console 2>&1 &
SERVER2=$!
echo "../bin/server -v -i 1 --config server-2.yaml -- $SERVER2"

../bin/server -v -i 2 --config server-3.yaml > results/server-3.console 2>&1 &
SERVER3=$!
echo "../bin/server -v -i 2 --config server-3.yaml -- $SERVER3"

../bin/server -v -i 3 --config server-4.yaml > results/server-4.console 2>&1 &
SERVER4=$!
echo "../bin/server -v -i 3 --config server-4.yaml -- $SERVER4"

../bin/server -v -i 4 --config server-5.yaml > results/server-5.console 2>&1 &
SERVER5=$!
echo "../bin/server -v -i 4 --config server-5.yaml -- $SERVER5"

finish() {
    echo "STOPPING SERVERS..."
    # jobs -p
    kill $SERVER1 || true
    kill $SERVER2 || true
    kill $SERVER3 || true
    kill $SERVER4 || true
    kill $SERVER5 || true
    tail results/*
}

trap finish EXIT

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
