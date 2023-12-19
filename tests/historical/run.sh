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

RESULTS=$1
GOLDOUTPUT=$2
NDF=$3

DEBUGLEVEL=${DEBUGLEVEL-1}

CLIENTOUT=$RESULTS/clients
CLIENTCLEAN=$RESULTS/clients-cleaned

mkdir -p $CLIENTOUT
mkdir -p $CLIENTCLEAN

#export GRPC_GO_LOG_VERBOSITY_LEVEL=99
#export GRPC_GO_LOG_SEVERITY_LEVEL=info

###############################################################################
# Test  Historical Rounds
###############################################################################

CLIENTOPTS="--password hello --ndf $NDF --verify-sends --sendDelay 100 --waitTimeout 360 -v $DEBUGLEVEL"

echo "FORCING HISTORICAL ROUNDS..."
FH1ID=$(bin/client init -s blobs/35 -l $CLIENTOUT/client35.log --password hello --ndf $NDF --writeContact $CLIENTOUT/FH1-contact.bin -v $DEBUGLEVEL)
FH2ID=$(bin/client init -s blobs/36 -l $CLIENTOUT/client36.log --password hello --ndf $NDF --writeContact $CLIENTOUT/FH2-contact.bin -v $DEBUGLEVEL)
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS --forceHistoricalRounds --unsafe -l $CLIENTOUT/client35.log -s blobs/35 --destid b64:$FH2ID --sendCount 5 --receiveCount 5 -m \"Hello from 35, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client35.txt  &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS --forceHistoricalRounds --unsafe -l $CLIENTOUT/client36.log -s blobs/36 --destid b64:$FH1ID --sendCount 5 --receiveCount 5 -m \"Hello from 36, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client36.txt  &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

echo "FORCING MESSAGE PICKUP RETRY... "
FM1ID=$(bin/client init -s blobs/22 -l $CLIENTOUT/client22.log --password hello --ndf $NDF --writeContact $CLIENTOUT/FM1-contact.bin -v $DEBUGLEVEL)
FM2ID=$(bin/client init -s blobs/23 -l $CLIENTOUT/client23.log --password hello --ndf $NDF --writeContact $CLIENTOUT/FM2-contact.bin -v $DEBUGLEVEL)
# Higher timeouts for this test to allow message pickup retry to function
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS --forceMessagePickupRetry -l $CLIENTOUT/client22.log -s blobs/22 --destid b64:$FM2ID --sendCount 5 --receiveCount 5 --unsafe -m \"Hello from 22, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client22.txt  &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS --forceMessagePickupRetry -l $CLIENTOUT/client23.log -s blobs/23  --destid b64:$FM1ID --sendCount 5 --receiveCount 5 --unsafe -m \"Hello from 23, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client23.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
echo "FIXME: The command above causes an UNEXPECTED failure and should be FIXED!"
wait $PIDVAL
wait $PIDVAL2

###############################################################################
# Check output
###############################################################################

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

set +x
diff -aru $GOLDOUTPUT $CLIENTCLEAN
