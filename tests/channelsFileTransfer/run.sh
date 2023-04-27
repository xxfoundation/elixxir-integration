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

CHANFILERESULTS=$1
GOLDOUTPUT=$2
NDF=$3

DEBUGLEVEL=${DEBUGLEVEL-1}

CLIENTOUT=$CHANFILERESULTS/clients
CLIENTCLEAN=$CHANFILERESULTS/clients-cleaned

mkdir -p $CLIENTOUT
mkdir -p $CLIENTCLEAN

#export GRPC_GO_LOG_VERBOSITY_LEVEL=99
#export GRPC_GO_LOG_SEVERITY_LEVEL=info

###############################################################################
# Test Channels File Transfer
###############################################################################

echo "TESTING CHANNELS FILE TRANSFER..."

CLIENTOPTS="--password hello --ndf $NDF --verify-sends --sendDelay 100 --waitTimeout 360 -v $DEBUGLEVEL"

# Initialize creator of channel and file sender
CLIENTCMD="timeout 300s bin/client channelsFileTransfer -s blobs/0 $CLIENTOPTS -l $CLIENTOUT/client0.log --ftChannelPath $CLIENTOUT/channel.chan --ftChannelIdentityPath $CLIENTOUT/channel0.id --ftNewChannel --ftChannelName MyFileTransferChannel --ftSendToChannel --file LoremIpsum.txt --ftFilePreviewString \"Lorem ipsum dolor sit amet, consectetur adipiscing elit.\" --ftMaxThroughput 700 --ftRetry 0 --ftOutput $CLIENTOUT/channel0_download.txt"
eval $CLIENTCMD > $CLIENTOUT/client0.txt 2>&1 &
PIDVAL0=$!
echo "$CLIENTCMD -- $PIDVAL0"

# Wait for the channel info file to be created
while [ ! -s $CLIENTOUT/channel.chan ]; do
    sleep 1
    echo -n "."
done
echo

# Initialize three clients to join the channel and receive the file
CLIENTCMD="timeout 300s bin/client channelsFileTransfer -s blobs/1 -l $CLIENTOUT/client1.log $CLIENTOPTS --ftChannelPath $CLIENTOUT/channel.chan --ftChannelIdentityPath $CLIENTOUT/channel1.id --ftJoinChannel --ftOutput $CLIENTOUT/channel1_download.txt"
eval $CLIENTCMD > $CLIENTOUT/client1.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="timeout 300s bin/client channelsFileTransfer -s blobs/2 -l $CLIENTOUT/client2.log $CLIENTOPTS --ftChannelPath $CLIENTOUT/channel.chan --ftChannelIdentityPath $CLIENTOUT/channel2.id --ftJoinChannel --ftOutput $CLIENTOUT/channel2_download.txt"
eval $CLIENTCMD > $CLIENTOUT/client2.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
CLIENTCMD="timeout 300s bin/client channelsFileTransfer -s blobs/3 -l $CLIENTOUT/client3.log $CLIENTOPTS --ftChannelPath $CLIENTOUT/channel.chan --ftChannelIdentityPath $CLIENTOUT/channel3.id --ftJoinChannel --ftOutput $CLIENTOUT/channel3_download.txt"
eval $CLIENTCMD > $CLIENTOUT/client3.txt 2>&1 &
PIDVAL3=$!
echo "$CLIENTCMD -- $PIDVAL3"

wait $PIDVAL0
wait $PIDVAL1
wait $PIDVAL2
wait $PIDVAL3

echo "TESTS EXITED SUCCESSFULLY, CHECKING OUTPUT..."

cp $CLIENTOUT/*.txt $CLIENTCLEAN/

sed -i.bak 's/Sending\ to\ .*\:/Sent:/g' $CLIENTCLEAN/client*.txt
sed -i.bak 's/Message\ from\ .*, .* Received:/Received:/g' $CLIENTCLEAN/client*.txt
sed -i.bak 's/ERROR.*Signature/Signature/g' $CLIENTCLEAN/client*.txt
sed -i.bak 's/[Aa]uthenticat.*$//g' $CLIENTCLEAN/client*.txt
rm $CLIENTCLEAN/client*.txt.bak

for C in $(ls -1 $CLIENTCLEAN | grep -v _download.txt); do
    sort -o tmp $CLIENTCLEAN/$C  || true
    cp tmp $CLIENTCLEAN/$C
done


set +x
diff -aru $GOLDOUTPUT $CLIENTCLEAN
