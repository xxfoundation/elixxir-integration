# NOTE: This is verbose on purpose.
################################################################################
## Initial Set Up & Clean Up of Past Runs
################################################################################

set -e

if [ $# -gt 3 ]
then
    echo "usage: $0 results_dir golds_dir"
    exit
fi

LOCALRESULTS=$1
GOLDOUTPUT=$2
NDF=$3

DEBUGLEVEL=${DEBUGLEVEL-1}

CLIENTOUT=$LOCALRESULTS/clients
CLIENTCLEAN=$LOCALRESULTS/clients-cleaned

mkdir -p $CLIENTOUT
mkdir -p $CLIENTCLEAN

CLIENTOPTS="--password hello --ndf $NDF --verify-sends --sendDelay 100 --waitTimeout 360 -v $DEBUGLEVEL"

#export GRPC_GO_LOG_VERBOSITY_LEVEL=99
#export GRPC_GO_LOG_SEVERITY_LEVEL=info

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
            CLIENTCMD="timeout 240s bin/client $CLIENTOPTS -l $CLIENTOUT/client$cid$nid.log -s blobs/$cid --unsafe --sendid $cid --destid $nid --sendCount 20 --receiveCount 20 -m \"Hello, $nid\""
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

###############################################################################
# Test  Basic Client
###############################################################################


echo "RUNNING BASIC CLIENTS..."
runclients
echo "RUNNING BASIC CLIENTS (2nd time)..."
runclients

# Send E2E messages between a single user
echo "TEST E2E WITH PRECANNED USERS..."
CLIENTCMD="timeout 240s bin/client  $CLIENTOPTS -l $CLIENTOUT/client9.log --sendCount 2 --receiveCount 2 -s blobs/9 --sendid 9 --destid 9 -m \"Hi 9->9, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client9.txt 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
CLIENTCMD="timeout 240s bin/client  $CLIENTOPTS -l $CLIENTOUT/client9.log --sendCount 2 --receiveCount 2 -s blobs/9 --sendid 9 --destid 9 -m \"Hi 9->9, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client9.txt 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS -l $CLIENTOUT/client18.log --sendCount 2 --receiveCount 2 -s blobs/18 --slowPolling --sendid 18 --destid 18 -m \"Hi 18->18, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client18.txt 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL


# Send E2E messages between two users
CLIENTCMD="timeout 240s bin/client  $CLIENTOPTS -l $CLIENTOUT/client9.log --sendCount 3 --receiveCount 3 -s blobs/9 --sendid 9 --destid 18 -m \"Hi 9->18, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client9.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS -l $CLIENTOUT/client18.log --sendCount 3 --receiveCount 3 -s blobs/18 --sendid 18 --destid 9 -m \"Hi 18->9, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client18.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL1
wait $PIDVAL2


# Send multiple E2E encrypted messages between users that discovered each other
echo "SENDING MESSAGES TO PRECANNED USERS AND FORCING A REKEY..."
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS -l $CLIENTOUT/client18_rekey.log --sendCount 20 --receiveCount 20 --destid 9 -s blobs/18 -m \"Hello, 9, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client18_rekey.txt 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS -l $CLIENTOUT/client9_rekey.log --sendCount 20 --receiveCount 20 --destid 18 -s blobs/9 -m \"Hello, 18, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client9_rekey.txt 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

echo "FORCING HISTORICAL ROUNDS... (NON-E2E, PRECAN)"
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS --forceHistoricalRounds --unsafe -l $CLIENTOUT/client33.log -s blobs/33 --sendid 1 --destid 2 --sendCount 5 --receiveCount 5 -m \"Hello from 1, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client33.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS --forceHistoricalRounds --unsafe -l $CLIENTOUT/client34.log -s blobs/34 --sendid 2 --destid 1 --sendCount 5 --receiveCount 5 -m \"Hello from 2, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client34.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

echo "FORCING MESSAGE PICKUP RETRY... (NON-E2E, PRECAN)"
# Higher timeouts for this test to allow message pickup retry to function
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS --forceMessagePickupRetry --unsafe -l $CLIENTOUT/client20.log -s blobs/20 --sendid 20 --destid 21 --sendCount 5 --receiveCount 5 -m \"Hello from 20, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client20.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS --forceMessagePickupRetry --unsafe -l $CLIENTOUT/client21.log -s blobs/21 --sendid 21 --destid 20 --sendCount 5 --receiveCount 5 -m \"Hello from 21, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client21.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

echo "TESTS EXITED SUCCESSFULLY, CHECKING OUTPUT..."

cp $CLIENTOUT/*.txt $CLIENTCLEAN/

sed -i.bak 's/Sending\ to\ .*\:/Sent:/g' $CLIENTCLEAN/client*.txt
sed -i.bak 's/Message\ from\ .*, .* Received:/Received:/g' $CLIENTCLEAN/client*.txt
sed -i.bak 's/ERROR.*Signature/Signature/g' $CLIENTCLEAN/client*.txt
sed -i.bak 's/[Aa]uthenticat.*$//g' $CLIENTCLEAN/client*.txt
rm $CLIENTCLEAN/client*.txt.bak

for C in $(ls -1 $CLIENTCLEAN | grep -v client11[01]); do
    sort -o tmp $CLIENTCLEAN/$C  || true
    cp tmp $CLIENTCLEAN/$C
    # uniq tmp $CLIENTCLEAN/$C || true
done

set -e

set +x
diff -aru $GOLDOUTPUT $CLIENTCLEAN

echo "NO OUTPUT ERRORS, SUCCESS!"
