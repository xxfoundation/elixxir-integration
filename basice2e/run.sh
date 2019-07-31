#!/bin/sh

# NOTE: This is verbose on purpose.

set -e
set -x

rm -fr results || true
rm blob* || true

SERVERLOGS=results/servers
GATEWAYLOGS=results/gateways
CLIENTOUT=results/clients
DUMMYOUT=results/dummy.console
UDBOUT=results/udb.console

CLIENTOPTS="-n ndf.json --skipNDFVerification"

mkdir -p $SERVERLOGS
mkdir -p $GATEWAYLOGS
mkdir -p $CLIENTOUT

echo "STARTING SERVERS..."

PERMCMD="../bin/permissioning -c permissioning.yaml -k dsa.json"
$PERMCMD > $SERVERLOGS/permissioning.log 2>&1 &
PIDVAL=$!
echo "$PERMCMD -- $PIDVAL"

for SERVERID in $(seq 5 -1 1)
do
    IDX=$(($SERVERID - 1))
    SERVERCMD="../bin/server -v -i $IDX --roundBufferTimeout 300s --config server-$SERVERID.yaml --keyPairOverride dsa.json"
    if [ $SERVERID -eq 4 ]; then
        sleep 15 # This will force a CDE timeout
    fi
    $SERVERCMD > $SERVERLOGS/server-$SERVERID.console 2>&1 &
    PIDVAL=$!
    echo "$SERVERCMD -- $PIDVAL"
done

sleep 15 # Give servers some time to boot

# Start gateways
for GWID in $(seq 5 -1 1)
do
    IDX=$(($GWID - 1))
    GATEWAYCMD="../bin/gateway -v -i $IDX --config gateway-$GWID.yaml"
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
    tail $SERVERLOGS/*
    tail $CLIENTOUT/*
    diff -ruN clients.goldoutput $CLIENTOUT
}

trap finish EXIT
trap finish INT

sleep 15 # FIXME: We should not need this, but the servers don't respond quickly
         #        enough on boot right now.

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
            CLIENTCMD="timeout 80s ../bin/client $CLIENTOPTS -f blob$cid -i $cid -d $nid -m \"Hello, $nid\""
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

# Start a user discovery bot server
UDBCMD="../bin/udb -v --config udb.yaml -n ndf.json"
$UDBCMD >> $UDBOUT 2>&1 &
PIDVAL=$!
echo $PIDVAL >> results/serverpids
echo "$UDBCMD -- $PIDVAL"

# Start a dummy client
DUMMYCMD="../bin/client $CLIENTOPTS -i 23 -d 23 -m \"dummy\" --dummyfrequency 2 -f blobdummy"
$DUMMYCMD >> $DUMMYOUT 2>&1 &
PIDVAL=$!
echo $PIDVAL >> results/serverpids
echo "$DUMMYCMD -- $PIDVAL"

# Register two users and then do UDB search on each other
CLIENTCMD="timeout 60s ../bin/client  $CLIENTOPTS -f blob9 -E spencer@elixxir.io -i 9 -d 9 -m \"Hi\""
eval $CLIENTCMD >> $CLIENTOUT/client9.out 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

CLIENTCMD="timeout 60s ../bin/client $CLIENTOPTS -f blob18 -E bernardo@elixxir.io -i 18 -d 3 -m \"SEARCH EMAIL spencer@elixxir.io\" --keyParams 3,4,2,1.0,2"
eval $CLIENTCMD >> $CLIENTOUT/client18.out 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

CLIENTCMD="timeout 60s ../bin/client $CLIENTOPTS -f blob9 -i 9 -d 3  -m \"SEARCH EMAIL bernardo@elixxir.io\" --keyParams 3,4,2,1.0,2"
eval $CLIENTCMD >> $CLIENTOUT/client9.out 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

# Send multiple E2E encrypted messages between users that discovered each other
CLIENTCMD="timeout 60s ../bin/client $CLIENTOPTS -i 18 -d 9 -f blob18 -m \"Hello, 9, with E2E Encryption\" --end2end --dummyfrequency 0.1"
eval $CLIENTCMD >> $CLIENTOUT/client18_rekey.out 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"

sleep 2

CLIENTCMD="timeout 60s ../bin/client $CLIENTOPTS -i 9 -d 18 -f blob9 -m \"Hello, 18, with E2E Encryption\" --end2end --dummyfrequency 0.1"
eval $CLIENTCMD >> $CLIENTOUT/client9_rekey.out 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

echo "RUNNING CLIENTS..."
runclients
echo "RUNNING CLIENTS (2nd time)..."
runclients

# Confirm all messages and rekeys by counting with grep
grep -ac "Sending Message to 9, Spencer" $CLIENTOUT/client18_rekey.out >> $CLIENTOUT/client18.out
grep -ac "Message from 9, Spencer Received" $CLIENTOUT/client18_rekey.out >> $CLIENTOUT/client18.out
grep -ac "Generated new send keys" $CLIENTOUT/client18_rekey.out  >> $CLIENTOUT/client18.out
grep -ac "Generated new receiving keys" $CLIENTOUT/client18_rekey.out  >> $CLIENTOUT/client18.out

grep -ac "Sending Message to 18, Bernardo" $CLIENTOUT/client9_rekey.out >> $CLIENTOUT/client9.out
grep -ac "Message from 18, Bernardo Received" $CLIENTOUT/client9_rekey.out >> $CLIENTOUT/client9.out
grep -ac "Generated new send keys" $CLIENTOUT/client9_rekey.out  >> $CLIENTOUT/client9.out
grep -ac "Generated new receiving keys" $CLIENTOUT/client9_rekey.out  >> $CLIENTOUT/client9.out
rm $CLIENTOUT/client18_rekey.out $CLIENTOUT/client9_rekey.out

diff -ruN clients.goldoutput $CLIENTOUT
cat $SERVERLOGS/*.log | grep "ERROR" > results/server-errors.txt || true
cat $SERVERLOGS/*.log | grep "FATAL" >> results/server-errors.txt || true
diff -ruN results/server-errors.txt noerrors.txt
cat $DUMMYOUT | grep "ERROR" > results/dummy-errors.txt || true
cat $DUMMYOUT | grep "FATAL" >> results/dummy-errors.txt || true
diff -ruN results/dummy-errors.txt noerrors.txt
IGNOREMSG="GetRoundBufferInfo: Error received: rpc error: code = Unknown desc = round buffer is empty"
cat $GATEWAYLOGS/*.log | grep "ERROR" | grep -v $IGNOREMSG > results/gateway-errors.txt || true
cat $GATEWAYLOGS/*.log | grep "FATAL" >> results/gateway-errors.txt || true
diff -ruN results/gateway-errors.txt noerrors.txt



echo "SUCCESS!"
