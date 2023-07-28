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

#export GRPC_GO_LOG_VERBOSITY_LEVEL=99
#export GRPC_GO_LOG_SEVERITY_LEVEL=info


###############################################################################
# Test Broadcast
###############################################################################


echo "TESTING BROADCAST CHANNELS..."

# New broadcast channel...
CLIENTCMD="timeout 240s bin/client broadcast --password hello --ndf $NDF --waitTimeout 1800 -l $CLIENTOUT/client130.log -s blobs/130 --new --channelName \"broadcast_test\" --description \"Integration test channel\" --chanPath results/integration-channel.json --keyPath results/integration-chan-key.pem --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client130.txt &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
wait $PIDVAL1

# Start client to listen for messages on the channel
CLIENTCMD="timeout 480s bin/client broadcast --password hello --ndf $NDF --waitTimeout 1800 -l $CLIENTOUT/client131.log -s blobs/131 --chanPath results/integration-channel.json --receiveCount 4"
eval $CLIENTCMD >> $CLIENTOUT/client131.txt &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"

sleep 10

# Send symmetric broadcast to channel
CLIENTCMD="timeout 240s bin/client broadcast --password hello --ndf $NDF --waitTimeout 360 -l $CLIENTOUT/client132.log -s blobs/132 --chanPath results/integration-channel.json --receiveCount 0 --sendDelay 5000 --symmetric \"Hello to symmetric channel from channel client 122!\""
eval $CLIENTCMD >> $CLIENTOUT/client132.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"

# Send asymmetric broadcast to channel
CLIENTCMD="timeout 240s bin/client broadcast --password hello --ndf $NDF --waitTimeout 360 -l $CLIENTOUT/client133.log -s blobs/133 --chanPath results/integration-channel.json --receiveCount 0 --sendDelay 5000 --keyPath results/integration-chan-key.pem --asymmetric \"Hello to asymmetric channel from channel client 123!\""
eval $CLIENTCMD >> $CLIENTOUT/client133.txt &
PIDVAL3=$!
echo "$CLIENTCMD -- $PIDVAL3"

# Send symmetric & asymmetric broadcasts to channel
CLIENTCMD="timeout 240s bin/client broadcast --password hello --ndf $NDF --waitTimeout 360 -l $CLIENTOUT/client134.log -s blobs/134 --chanPath results/integration-channel.json --receiveCount 0 --sendDelay 5000 --keyPath results/integration-chan-key.pem --asymmetric \"Hello to asymmetric channel from channel client 124!\" --symmetric \"Hello to symmetric channel from channel client 124!\""
eval $CLIENTCMD >> $CLIENTOUT/client134.txt &
PIDVAL4=$!
echo "$CLIENTCMD -- $PIDVAL4"

wait $PIDVAL2
wait $PIDVAL3
wait $PIDVAL4
wait $PIDVAL1

echo "BROADCAST CHANNELS FINISHED..."

########################################################################

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
