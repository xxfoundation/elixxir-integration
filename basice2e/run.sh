#!/bin/sh

# NOTE: This is verbose on purpose.

set -e

rm -fr results || true
rm blob* || true

mkdir -p .elixxir

SERVERLOGS=results/servers
GATEWAYLOGS=results/gateways
CLIENTOUT=results/clients
DUMMYOUT=results/dummy.console
UDBOUT=results/udb.console
CLIENTCLEAN=results/clients-cleaned

CLIENTOPTS="-n ndf.json --skipNDFVerification --noTLS"

mkdir -p $SERVERLOGS
mkdir -p $GATEWAYLOGS
mkdir -p $CLIENTOUT
mkdir -p $CLIENTCLEAN

echo "STARTING SERVERS..."

PERMCMD="../bin/permissioning -c permissioning.yaml -k dsa.json --noTLS"
$PERMCMD > $SERVERLOGS/permissioning.log 2>&1 &
PIDVAL=$!
echo "$PERMCMD -- $PIDVAL"

for SERVERID in $(seq 5 -1 1)
do
    IDX=$(($SERVERID - 1))
    SERVERCMD="../bin/server --disablePermissioning --noTLS -v -i $IDX --roundBufferTimeout 300s --config server-$SERVERID.yaml"
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
    GATEWAYCMD="../bin/gateway -v -i $IDX --disablePermissioning --noTLS --config gateway-$GWID.yaml"
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
    tail $CLIENTCLEAN/*
    diff -ruN clients.goldoutput $CLIENTCLEAN
}

trap finish EXIT
trap finish INT

sleep 15 # FIXME: We should not need this, but the servers don't respond quickly
         #        enough on boot right now.

runclients() {
    echo "Starting clients..."

    # Now send messages to each other
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
            CLIENTCMD="timeout 180s ../bin/client $CLIENTOPTS -f blob$cid -E email$cid@email.com -i $cid -d $nid -m \"Hello, $nid\""
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
UDBCMD="../bin/udb -v --config udb.yaml"
$UDBCMD >> $UDBOUT 2>&1 &
PIDVAL=$!
echo $PIDVAL >> results/serverpids
echo "$UDBCMD -- $PIDVAL"

sleep 10

# Start a dummy client
DUMMYCMD="../bin/client $CLIENTOPTS -i 23 -d 23 -m \"dummy\" --dummyfrequency 2 -f blobdummy"
$DUMMYCMD >> $DUMMYOUT 2>&1 &
PIDVAL=$!
echo $PIDVAL >> results/serverpids
echo "$DUMMYCMD -- $PIDVAL"

echo "RUNNING CLIENTS..."
runclients
echo "RUNNING CLIENTS (2nd time)..."
runclients

# Register two users and then do UDB search on each other
CLIENTCMD="timeout 60s ../bin/client  $CLIENTOPTS -f blob9 -E niamh@elixxir.io -i 9 -d 9 -m \"Hi\""
eval $CLIENTCMD >> $CLIENTOUT/client9.out 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

CLIENTCMD="timeout 60s ../bin/client $CLIENTOPTS -f blob18 -E bernardo@elixxir.io -i 18 -d 3 -m \"SEARCH EMAIL niamh@elixxir.io\" --keyParams 3,4,2,1.0,2"
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
eval $CLIENTCMD >> $CLIENTOUT/client18_rekey.out 2>&1 || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"

CLIENTCMD="timeout 60s ../bin/client $CLIENTOPTS -i 9 -d 18 -f blob9 -m \"Hello, 18, with E2E Encryption\" --end2end --dummyfrequency 0.1"
eval $CLIENTCMD >> $CLIENTOUT/client9_rekey.out 2>&1 || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"

set +e
wait $PIDVAL || true

# FIXME: Go into client and clean up it's output so this is not necessary
for C in $(ls -1 $CLIENTOUT); do
    # Remove the [CLIENT] Lines and cut them down
    cat $CLIENTOUT/$C | grep "[CLIENT]" | cut -d\  -f5- | grep -e "Received\:" -e "Sending Message" -e "Message from" > $CLIENTCLEAN/$C || true
    # Take the clean lines and add them
    cat $CLIENTOUT/$C | grep -v "[CLIENT]" | grep -e "Received\:" -e "Sending Message" -e "Message from" >> $CLIENTCLEAN/$C || true
done

# only expect up to 10c messages from the e2e clients
head -10 $CLIENTCLEAN/client9_rekey.out > $CLIENTCLEAN/client9.out || true
head -10 $CLIENTCLEAN/client18_rekey.out > $CLIENTCLEAN/client18.out || true
rm $CLIENTCLEAN/client9_rekey.out $CLIENTCLEAN/client18_rekey.out || true

for C in $(ls -1 $CLIENTCLEAN); do
    sort -o tmp $CLIENTCLEAN/$C  || true
    uniq tmp $CLIENTCLEAN/$C || true
done

set -e

diff -ruN clients.goldoutput $CLIENTCLEAN

cat $CLIENTOUT/* | grep -e "ERROR" -e "FATAL" > results/client-errors || true
diff -ruN results/client-errors.txt noerrors.txt
cat $SERVERLOGS/server-*.log | grep "ERROR" | grep -v "context" > results/server-errors.txt || true
cat $SERVERLOGS/server-*.log | grep "FATAL" | grep -v "context" | grep -v "database" >> results/server-errors.txt || true
diff -ruN results/server-errors.txt noerrors.txt
cat $DUMMYOUT | grep "ERROR" | grep -v "context" | grep -v "failed\ to\ read\ certificate" > results/dummy-errors.txt || true
cat $DUMMYOUT | grep "FATAL" | grep -v "context" >> results/dummy-errors.txt || true
diff -ruN results/dummy-errors.txt noerrors.txt
IGNOREMSG="GetRoundBufferInfo: Error received: rpc error: code = Unknown desc = round buffer is empty"
cat $GATEWAYLOGS/*.log | grep "ERROR" | grep -v "context" | grep -v "certificate" | grep -v "Failed to read key" | grep -v "$IGNOREMSG" > results/gateway-errors.txt || true
cat $GATEWAYLOGS/*.log | grep "FATAL" | grep -v "context" >> results/gateway-errors.txt || true
diff -ruN results/gateway-errors.txt noerrors.txt

echo "SUCCESS!"
