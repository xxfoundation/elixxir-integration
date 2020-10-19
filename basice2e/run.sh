#!/bin/sh

# NOTE: This is verbose on purpose.

set -e

rm -fr results || true
rm -fr blob* || true
rm server-5.qdstrm || true
rm server-5.qdrep || true

mkdir -p .elixxir

#export GRPC_GO_LOG_VERBOSITY_LEVEL=99
#export GRPC_GO_LOG_SEVERITY_LEVEL=info

SERVERLOGS=results/servers
GATEWAYLOGS=results/gateways
CLIENTOUT=results/clients
DUMMYOUT=results/dummy-console.txt
UDBOUT=results/udb-console.txt
CLIENTCLEAN=results/clients-cleaned

CLIENTOPTS="--password hello --ndf ndf.json --unsafe-channel-creation"

mkdir -p $SERVERLOGS
mkdir -p $GATEWAYLOGS
mkdir -p $CLIENTOUT
mkdir -p $CLIENTCLEAN

echo "STARTING SERVERS..."

PERMCMD="../bin/permissioning -c permissioning.yaml "
$PERMCMD > $SERVERLOGS/permissioning-console.txt 2>&1 &
PIDVAL=$!
echo "$PERMCMD -- $PIDVAL"

for SERVERID in $(seq 5 -1 1)
do
    IDX=$(($SERVERID - 1))
    SERVERCMD="../bin/server --config server-$SERVERID.yaml"
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
    GATEWAYCMD="../bin/gateway --config gateway-$GWID.yaml"
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
    grep -a "RID 1 ReceiveFinishRealtime END" results/servers/server-5.log > rid.txt || true
    cnt=$(($cnt + 1))
    echo -n "."
done

echo "DONE LETS DO STUFF"

# Start a user discovery bot server
# echo "STARTING UDB..."
# UDBCMD="../bin/udb --logLevel 3 --config udb.yaml -l 1"
# $UDBCMD >> $UDBOUT 2>&1 &
# PIDVAL=$!
# echo $PIDVAL >> results/serverpids
# echo "$UDBCMD -- $PIDVAL"

# rm rid.txt || true
# while [ ! -s rid.txt ] && [ $cnt -lt 30 ]; do
#     sleep 1
#     grep -a "Gateway Polling for Message Reception Begun" results/udb-console.txt > rid.txt || true
#     cnt=$(($cnt + 1))
#     echo -n "."
# done

# sleep 5

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
            mkdir -p blob$cid
            CLIENTCMD="timeout 120s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client$cid$nid.log -s blob$cid/blob$cid --unsafe --sendid $cid --destid $nid -m \"Hello, $nid\""
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

# Send E2E messages between a single user
mkdir -p blob9
mkdir -p blob18
echo "TEST E2E WITH PRECANNED USERS..."
CLIENTCMD="timeout 90s ../bin/client  $CLIENTOPTS -l $CLIENTOUT/client9.log --sendCount 2 --receiveCount 2 -s blob9/blob9 --sendid 9 --destid 9 -m \"Hi 9->9, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client9.txt 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
echo "TEST E2E WITH PRECANNED USERS..."
CLIENTCMD="timeout 90s ../bin/client  $CLIENTOPTS -l $CLIENTOUT/client9.log --sendCount 2 --receiveCount 2 -s blob9/blob9 --sendid 9 --destid 9 -m \"Hi 9->9, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client9.txt 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

# Send E2E messages between two users
CLIENTCMD="timeout 90s ../bin/client  $CLIENTOPTS -l $CLIENTOUT/client9.log --sendCount 1 --receiveCount 1 -s blob9/blob9 --sendid 9 --destid 18 -m \"Hi 9->18, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client9.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 90s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client18.log --sendCount 1 --receiveCount 1 -s blob18/blob18 --sendid 18 --destid 9 -m \"Hi 18->9, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client18.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL1
wait $PIDVAL2

CLIENTCMD="timeout 90s ../bin/client  $CLIENTOPTS -l $CLIENTOUT/client9.log --sendCount 5 --receiveCount 5 -s blob9/blob9 --sendid 9 --destid 18 -m \"Hi 9->18, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client9.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 90s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client18.log --sendCount 5 --receiveCount 5 -s blob18/blob18 --sendid 18 --destid 9 -m \"Hi 18->9, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client18.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL1
wait $PIDVAL2


# # Send multiple E2E encrypted messages between users that discovered each other
# echo "SENDING MESSAGES TO PRECANNED USERS AND FORCING A REKEY..."
# CLIENTCMD="timeout 180s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client18_rekey.log -c 20 -w 20 -i 18 -d 9 -s \"niamh@elixxir.io\" -f blob18/blob18 -m \"Hello, 9, with E2E Encryption\" --end2end"
# eval $CLIENTCMD >> $CLIENTOUT/client18_rekey.txt 2>&1 || true &
# PIDVAL=$!
# echo "$CLIENTCMD -- $PIDVAL"
# CLIENTCMD="timeout 180s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client9_rekey.log -c 20 -w 20 -i 9 -d 18 -s \"bernardo@elixxir.io\" -f blob9/blob9 -m \"Hello, 18, with E2E Encryption\" --end2end"
# eval $CLIENTCMD >> $CLIENTOUT/client9_rekey.txt 2>&1 || true &
# PIDVAL=$!
# echo "$CLIENTCMD -- $PIDVAL"
# set +e
# wait $PIDVAL || true


# # Register non-precanned users
# mkdir -p blob42
# mkdir -p blob43
# echo "REGISTERING NEW USERS..."
# CLIENTCMD="timeout 210s ../bin/client  $CLIENTOPTS -l $CLIENTOUT/client42.log -f blob42/blob42 -E rick42@elixxir.io -r FFFF"
# eval $CLIENTCMD >> $CLIENTOUT/client42.txt &
# PIDVAL=$!
# echo "$CLIENTCMD -- $PIDVAL"
# CLIENTCMD="timeout 210s ../bin/client  $CLIENTOPTS -l $CLIENTOUT/client43.log -f blob43/blob43 -E ben43@elixxir.io -r GGGG"
# eval $CLIENTCMD >> $CLIENTOUT/client43.txt &
# PIDVAL2=$!
# echo "$CLIENTCMD -- $PIDVAL"
# wait $PIDVAL
# wait $PIDVAL2

# # Have each non-precanned user search for each other
# echo "SEARCHING FOR NEW USERS..."
# CLIENTCMD="timeout 180s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -f blob42/blob42 -s \"ben43@elixxir.io\" --keyParams 3,4,2,1.0,2"
# eval $CLIENTCMD >> $CLIENTOUT/client42.txt &
# PIDVAL=$!
# echo "$CLIENTCMD -- $PIDVAL"
# CLIENTCMD="timeout 180s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -f blob43/blob43 -s \"rick42@elixxir.io\" --keyParams 3,4,2,1.0,2"
# eval $CLIENTCMD >> $CLIENTOUT/client43.txt &
# PIDVAL2=$!
# echo "$CLIENTCMD -- $PIDVAL"
# wait $PIDVAL
# wait $PIDVAL2

# # Extract generated user name from logs
# echo "EXTRACTING USER IDs FROM LOG FILES..."
# TMPID=$(cat $CLIENTOUT/client42.log | grep "Successfully registered user" | awk -F' ' '{print $8}')
# RICKID=${TMPID%?} # remove ! from end
# TMPID=$(cat $CLIENTOUT/client43.log | grep "Successfully registered user" | awk -F' ' '{print $8}')
# BENID=${TMPID%?} # remove ! from end

# # Non-precanned user messaging
# echo "SENDING E2E MESSAGES TO NEW USERS..."
# CLIENTCMD="timeout 210s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -c 1 -w 1 --dest64 $BENID -s \"ben43@elixxir.io\" -f blob42/blob42 -m \"Hello from Rick42, with E2E Encryption\" --end2end"
# eval $CLIENTCMD >> $CLIENTOUT/client42.txt || true &
# PIDVAL=$!
# echo "$CLIENTCMD -- $PIDVAL"
# CLIENTCMD="timeout 210s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -c 1 -w 1 --dest64 $RICKID -s \"rick42@elixxir.io\" -f blob43/blob43 -m \"Hello from Ben43, with E2E Encryption\" --end2end"
# eval $CLIENTCMD >> $CLIENTOUT/client43.txt || true &
# PIDVAL2=$!
# echo "$CLIENTCMD -- $PIDVAL"
# wait $PIDVAL
# wait $PIDVAL2


cp $CLIENTOUT/*.txt $CLIENTCLEAN/

# Ignore rekey for now
#rm $CLIENTCLEAN/*_rekey.txt

#sed -i 's/Sending\ Message\ to\ .*,\ :/Sent:/g' $CLIENTCLEAN/client4[23].txt
#sed -i 's/Message\ from\ .*, .* Received:/Received:/g' $CLIENTCLEAN/client4[23].txt

# for C in $(ls -1 $CLIENTCLEAN); do
#     sort -o tmp $CLIENTCLEAN/$C  || true
#     uniq tmp $CLIENTCLEAN/$C || true
# done

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
