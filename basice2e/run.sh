#!/bin/sh

# NOTE: This is verbose on purpose.

set -e

rm -fr results || true
rm blob* || true

mkdir -p .elixxir

#export GRPC_GO_LOG_VERBOSITY_LEVEL=99
#export GRPC_GO_LOG_SEVERITY_LEVEL=info

SERVERLOGS=results/servers
GATEWAYLOGS=results/gateways
CLIENTOUT=results/clients
DUMMYOUT=results/dummy-console.txt
UDBOUT=results/udb-console.txt
CLIENTCLEAN=results/clients-cleaned

CLIENTOPTS="-v -n ndf.json --skipNDFVerification -P dummypassword "

mkdir -p $SERVERLOGS
mkdir -p $GATEWAYLOGS
mkdir -p $CLIENTOUT
mkdir -p $CLIENTCLEAN

# Start a user discovery bot server
echo "STARTING UDB..."
UDBCMD="../bin/udb --logLevel 3 --config udb.yaml -l 1"
$UDBCMD >> $UDBOUT 2>&1 &
PIDVAL=$!
echo $PIDVAL >> results/serverpids
echo "$UDBCMD -- $PIDVAL"

echo "STARTING SERVERS..."

PERMCMD="../bin/permissioning -c permissioning.yaml "
$PERMCMD > $SERVERLOGS/permissioning-console.txt 2>&1 &
PIDVAL=$!
echo "$PERMCMD -- $PIDVAL"

for SERVERID in $(seq 6 -1 1)
do
    IDX=$(($SERVERID - 1))
    SERVERCMD="../bin/server -i $IDX --roundBufferTimeout 300s --config server-$SERVERID.yaml"
    $SERVERCMD > $SERVERLOGS/server-$SERVERID-console.txt 2>&1 &
    PIDVAL=$!
    echo "$SERVERCMD -- $PIDVAL"
done

# Start gateways
for GWID in $(seq 6 -1 1)
do
    IDX=$(($GWID - 1))
    GATEWAYCMD="../bin/gateway  -i $IDX  --config gateway-$GWID.yaml"
    $GATEWAYCMD > $GATEWAYLOGS/gateway-$GWID-console.txt 2>&1 &
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
    #tail $SERVERLOGS/*
    #tail $CLIENTCLEAN/*
    #diff -ruN clients.goldoutput $CLIENTCLEAN
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
    cat results/servers/server-5.log | grep "RID 0 ReceiveFinishRealtime END" > rid.txt || true
    cnt=$(($cnt + 1))
    echo -n "."
done

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
            CLIENTCMD="timeout 60s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client$cid$nid.log -f blob$cid -E email$cid@email.com -i $cid -d $nid -m \"Hello, $nid\""
            eval $CLIENTCMD >> $CLIENTOUT/client$cid$nid.txt 2>&1 &
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

echo "RUNNING BASIC CLIENTS..."
runclients
echo "RUNNING BASIC CLIENTS (2nd time)..."
runclients

# Register two users and then do UDB search on each other
echo "REGISTERING AND SEARCHING WITH PRECANNED USERS..."
CLIENTCMD="timeout 90s ../bin/client  $CLIENTOPTS -l $CLIENTOUT/client9.log -f blob9 -E niamh@elixxir.io -i 9 -d 9 -m \"Hi\""
eval $CLIENTCMD >> $CLIENTOUT/client9.txt 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
CLIENTCMD="timeout 90s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client18.log -f blob18 -E bernardo@elixxir.io -i 18 -d 9 -s \"niamh@elixxir.io\" --keyParams 3,4,2,1.0,2"
eval $CLIENTCMD >> $CLIENTOUT/client18.txt 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
CLIENTCMD="timeout 90s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client9.log -f blob9 -i 9 -d 18 -s \"bernardo@elixxir.io\" --keyParams 3,4,2,1.0,2"
eval $CLIENTCMD >> $CLIENTOUT/client9.txt 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

# Send multiple E2E encrypted messages between users that discovered each other
echo "SENDING MESSAGES TO PRECANNED USERS AND FORCING A REKEY..."
CLIENTCMD="timeout 180s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client18_rekey.log -c 20 -w 20 -i 18 -d 9 -s \"niamh@elixxir.io\" -f blob18 -m \"Hello, 9, with E2E Encryption\" --end2end"
eval $CLIENTCMD >> $CLIENTOUT/client18_rekey.txt 2>&1 || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 180s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client9_rekey.log -c 20 -w 20 -i 9 -d 18 -s \"bernardo@elixxir.io\" -f blob9 -m \"Hello, 18, with E2E Encryption\" --end2end"
eval $CLIENTCMD >> $CLIENTOUT/client9_rekey.txt 2>&1 || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
set +e
wait $PIDVAL || true


# Register non-precanned users
echo "REGISTERING NEW USERS..."
CLIENTCMD="timeout 180s ../bin/client  $CLIENTOPTS -l $CLIENTOUT/client42.log -f blob42 -E rick42@elixxir.io -r FFFF"
eval $CLIENTCMD >> $CLIENTOUT/client42.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 180s ../bin/client  $CLIENTOPTS -l $CLIENTOUT/client43.log -f blob43 -E ben43@elixxir.io -r GGGG"
eval $CLIENTCMD >> $CLIENTOUT/client43.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

# Have each non-precanned user search for each other
echo "SEARCHING FOR NEW USERS..."
CLIENTCMD="timeout 180s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -f blob42 -s \"ben43@elixxir.io\" --keyParams 3,4,2,1.0,2"
eval $CLIENTCMD >> $CLIENTOUT/client42.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 180s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -f blob43 -s \"rick42@elixxir.io\" --keyParams 3,4,2,1.0,2"
eval $CLIENTCMD >> $CLIENTOUT/client43.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

# Extract generated user name from logs
echo "EXTRACTING USER IDs FROM LOG FILES..."
TMPID=$(cat $CLIENTOUT/client42.log | grep "Successfully registered user" | awk -F' ' '{print $8}')
RICKID=${TMPID%?} # remove ! from end
TMPID=$(cat $CLIENTOUT/client43.log | grep "Successfully registered user" | awk -F' ' '{print $8}')
BENID=${TMPID%?} # remove ! from end

# Non-precanned user messaging
echo "SENDING E2E MESSAGES TO NEW USERS..."
CLIENTCMD="timeout 180s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -c 1 -w 1 --dest64 $BENID -s \"ben43@elixxir.io\" -f blob42 -m \"Hello from Rick42, with E2E Encryption\" --end2end"
eval $CLIENTCMD >> $CLIENTOUT/client42.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 180s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -c 1 -w 1 --dest64 $RICKID -s \"rick42@elixxir.io\" -f blob43 -m \"Hello from Ben43, with E2E Encryption\" --end2end"
eval $CLIENTCMD >> $CLIENTOUT/client43.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2


cp $CLIENTOUT/*.txt $CLIENTCLEAN/

# Ignore rekey for now
rm $CLIENTCLEAN/*_rekey.txt

sed -i 's/Sending\ Message\ to\ .*,\ :/Sent:/g' $CLIENTCLEAN/client4[23].txt
sed -i 's/Message\ from\ .*, .* Received:/Received:/g' $CLIENTCLEAN/client4[23].txt

for C in $(ls -1 $CLIENTCLEAN); do
    sort -o tmp $CLIENTCLEAN/$C  || true
    uniq tmp $CLIENTCLEAN/$C || true
done

set -e


echo "TESTS EXITED SUCCESSFULLY, CHECKING OUTPUT..."
set +x
diff -ruN clients.goldoutput $CLIENTCLEAN

cat $CLIENTOUT/* | strings | grep -e "ERROR" -e "FATAL" > results/client-errors || true
diff -ruN results/client-errors.txt noerrors.txt
cat $SERVERLOGS/server-*.log | grep "ERROR" | grep -v "context" | grep -v "metrics" | grep -v "database" > results/server-errors.txt || true
cat $SERVERLOGS/server-*.log | grep "FATAL" | grep -v "context" | grep -v "transport is closing" | grep -v "database" >> results/server-errors.txt || true
diff -ruN results/server-errors.txt noerrors.txt
cat $DUMMYOUT | grep "ERROR" | grep -v "context" | grep -v "failed\ to\ read\ certificate" > results/dummy-errors.txt || true
cat $DUMMYOUT | grep "FATAL" | grep -v "context" >> results/dummy-errors.txt || true
diff -ruN results/dummy-errors.txt noerrors.txt
IGNOREMSG="GetRoundBufferInfo: Error received: rpc error: code = Unknown desc = round buffer is empty"
cat $GATEWAYLOGS/*.log | grep "ERROR" | grep -v "context" | grep -v "certificate" | grep -v "Failed to read key" | grep -v "$IGNOREMSG" > results/gateway-errors.txt || true
cat $GATEWAYLOGS/*.log | grep "FATAL" | grep -v "context" | grep -v "transport is closing" >> results/gateway-errors.txt || true
diff -ruN results/gateway-errors.txt noerrors.txt

echo "NO OUTPUT ERRORS, SUCCESS!"
