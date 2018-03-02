#!/bin/sh

# NOTE: This is verbose on purpose.

set -e

mkdir -p results

../bin/server -v -i 0 --config server-1.yaml > results/server-1.console 2>&1 &
SERVER1=$!
../bin/server -v -i 1 --config server-2.yaml > results/server-2.console 2>&1 &
SERVER2=$!
../bin/server -v -i 2 --config server-3.yaml > results/server-3.console 2>&1 &
SERVER3=$!
../bin/server -v -i 3 --config server-4.yaml > results/server-4.console 2>&1 &
SERVER4=$!
../bin/server -v -i 4 --config server-5.yaml > results/server-5.console 2>&1 &
SERVER5=$!

echo "STARTED SERVERS with PIDs:"
echo $SERVER1
echo $SERVER2
echo $SERVER3
echo $SERVER4
echo $SERVER5

finish() {
    echo "STOPPING SERVERS..."
    kill $SERVER1
    kill $SERVER2
    kill $SERVER3
    kill $SERVER4
    kill $SERVER5
}

trap finish EXIT

sleep 25 # FIXME: We should not need this, but the servers don't respond quickly
         #        enough on boot right now.

LASTNODE="localhost:50004"


echo "STARTING CLIENTS..."
CTR=0
for cid in 1 2 3 4; do
    for nid in 1 2 3 4; do
        ../bin/client -s $LASTNODE -i $cid -d $nid -m "Hello, $nid" > results/client$cid$nid.out 2>&1 &
        eval CLIENTS${CTR}=$!
        CTR=$(($CTR + 1))
    done
done

echo "WAITING FOR CLIENTS TO EXIT..."
for i in $(seq 0 $CTR); do
    eval wait $CLIENTS${i}
done

