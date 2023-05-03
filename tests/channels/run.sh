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

CHANRESULTS=$1
GOLDOUTPUT=$2
NDF=$3

DEBUGLEVEL=${DEBUGLEVEL-1}

CLIENTOUT=$CHANRESULTS/clients
CLIENTCLEAN=$CHANRESULTS/clients-cleaned

mkdir -p $CLIENTOUT
mkdir -p $CLIENTCLEAN

###############################################################################
# Test Channels
###############################################################################

echo "TESTING CHANNELS..."

CLIENTOPTS="--password hello --ndf $NDF --verify-sends --sendDelay 100 --waitTimeout 360 -v $DEBUGLEVEL"

# Initialize creator of channel (will use default channel file path in CLI)
CLIENTCMD="timeout 300s bin/client channels -s blobs/500 $CLIENTOPTS -l $CLIENTOUT/client500.log --receiveCount 0 --channelPath $CLIENTOUT/channel500.chan  --channelIdentityPath $CLIENTOUT/channel500.id --newChannel"
eval $CLIENTCMD > $CLIENTOUT/client500.txt 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"

wait $PIDVAL

# Have client which created channel send message to channel
CLIENTCMD="timeout 300s bin/client channels -s blobs/500 -l $CLIENTOUT/client500.log $CLIENTOPTS --receiveCount 3 --channelPath $CLIENTOUT/channel500.chan --channelIdentityPath $CLIENTOUT/channel500.id --sendToChannel --message \"Hello, channel, this is 500\""
eval $CLIENTCMD >> $CLIENTOUT/client500.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"

# Initialize client which will join channel (will use default channel file path in CLI)
CLIENTCMD="timeout 300s bin/client channels -s blobs/501 -l $CLIENTOUT/client501.log $CLIENTOPTS --receiveCount 3 --channelPath $CLIENTOUT/channel500.chan --channelIdentityPath $CLIENTOUT/channel501.id --joinChannel --sendToChannel --message \"Hello, channel, this is 501\""
eval $CLIENTCMD > $CLIENTOUT/client501.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"

# Initialize another client which will join channel (will use default channel file path in CLI)
CLIENTCMD="timeout 420s bin/client channels -s blobs/502 -l $CLIENTOUT/client502.log $CLIENTOPTS --receiveCount 3 --channelPath $CLIENTOUT/channel500.chan --channelIdentityPath $CLIENTOUT/channel502.id --joinChannel --sendToChannel --message \"Hello, channel, this is 502\""
eval $CLIENTCMD > $CLIENTOUT/client502.txt 2>&1 &
PIDVAL3=$!
echo "$CLIENTCMD -- $PIDVAL3"

wait $PIDVAL1
wait $PIDVAL2
wait $PIDVAL3

# All clients will leave the channel
CLIENTCMD="timeout 300s bin/client channels -s blobs/500 -l $CLIENTOUT/client500.log $CLIENTOPTS --receiveCount 0 --channelPath $CLIENTOUT/channel500.chan  --channelIdentityPath $CLIENTOUT/channel500.id --leaveChannel"
eval $CLIENTCMD >> $CLIENTOUT/client500.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"

CLIENTCMD="timeout 300s bin/client channels -s blobs/501 -l $CLIENTOUT/client501.log $CLIENTOPTS --receiveCount 0 --channelPath $CLIENTOUT/channel500.chan  --channelIdentityPath $CLIENTOUT/channel501.id --leaveChannel"
eval $CLIENTCMD >> $CLIENTOUT/client501.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"

# Initialize another client which will join channel (will use default channel file path in CLI)
CLIENTCMD="timeout 300s bin/client channels -s blobs/502 -l $CLIENTOUT/client502.log $CLIENTOPTS --receiveCount 0 --channelPath $CLIENTOUT/channel500.chan  --channelIdentityPath $CLIENTOUT/channel502.id --leaveChannel"
eval $CLIENTCMD >> $CLIENTOUT/client502.txt 2>&1 &
PIDVAL3=$!
echo "$CLIENTCMD -- $PIDVAL3"
sleep 20
wait $PIDVAL3
wait $PIDVAL2
wait $PIDVAL1


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
