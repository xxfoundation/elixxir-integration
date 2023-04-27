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

FILETRANSFERRESULTS=$1
GOLDOUTPUT=$2
NDF=$3

DEBUGLEVEL=${DEBUGLEVEL-1}

CLIENTOUT=$FILETRANSFERRESULTS/clients
CLIENTCLEAN=$FILETRANSFERRESULTS/clients-cleaned

mkdir -p $CLIENTOUT
mkdir -p $CLIENTCLEAN

#export GRPC_GO_LOG_VERBOSITY_LEVEL=99
#export GRPC_GO_LOG_SEVERITY_LEVEL=info

###############################################################################
# Test  File Transfer
###############################################################################

CLIENTOPTS="--password hello --ndf $NDF --verify-sends --sendDelay 100 --waitTimeout 360 -v $DEBUGLEVEL"
CLIENTFILETRANSFEROPTS="--password hello --waitTimeout 600 --ndf $NDF -v $DEBUGLEVEL"

echo "TESTING FILE TRANSFER..."

# Create authenticated channel between client 110 and 111
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS -l $CLIENTOUT/client110.log -s blobs/110 --writeContact $CLIENTOUT/client110-contact.bin --unsafe -m \"Hello from contact 110 to myself, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client110.txt &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
wait $PIDVAL1
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS -l $CLIENTOUT/client111.log -s blobs/111 --writeContact $CLIENTOUT/client111-contact.bin --destfile $CLIENTOUT/client110-contact.bin --send-auth-request --unsafe-channel-creation --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client111.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"

while [ ! -s $CLIENTOUT/client111-contact.bin ]; do
    sleep 1
    echo -n "."
done
echo

TMPID=$(cat $CLIENTOUT/client110.log | grep -a "User\:" | awk -F' ' '{print $5}')
CLIENT110ID=${TMPID}
echo "CLIENT 110 ID: $CLIENT110ID"
TMPID=$(cat $CLIENTOUT/client111.log | grep -a "User\:" | awk -F' ' '{print $5}')
CLIENT111ID=${TMPID}
echo "CLIENT 111 ID: $CLIENT111ID"

# Client 110 will now wait for client 111's E2E Auth channel request and confirm
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client110.log -s blobs/110 --destfile $CLIENTOUT/client111-contact.bin --sendCount 0 --receiveCount 0 --accept-channel --auth-timeout 360"
eval $CLIENTCMD >> $CLIENTOUT/client110.txt &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
wait $PIDVAL1
wait $PIDVAL2

# Client 111 sends a file to client 110
CLIENTCMD="timeout 360s bin/client fileTransfer -s blobs/110 -l $CLIENTOUT/client110.log $CLIENTFILETRANSFEROPTS"
eval $CLIENTCMD > $CLIENTOUT/client110.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="timeout 700s bin/client fileTransfer -s blobs/111 -l $CLIENTOUT/client111.log $CLIENTFILETRANSFEROPTS --sendFile $CLIENTOUT/client110-contact.bin --filePath LoremIpsum.txt --filePreviewString \"Lorem ipsum dolor sit amet, consectetur adipiscing elit.\" --maxThroughput 1000 --retry 0"
eval $CLIENTCMD > $CLIENTOUT/client111.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL1
wait $PIDVAL2

echo "FILE TRANSFER FINISHED..."

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
