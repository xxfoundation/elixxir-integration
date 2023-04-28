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
# Test DMs
###############################################################################

CLIENTDMOPTS="--password hello --ndf $NDF --waitTimeout 360 -v $DEBUGLEVEL"

echo "SENDING DM MESSAGES TO NEW USERS"
# The goal here is to try 3 things:
# 1. Send a DM to myself
# 2. Receive a DM from someone else
# 3. Send a reply to the user who sent me a message in #2
CLIENTCMD="timeout 360s bin/client $CLIENTDMOPTS -l $CLIENTOUT/client1.log -s blobs/1 dm -m \"Hello from Rick Prime to myself via DM\" --receiveCount 3"
eval $CLIENTCMD >> $CLIENTOUT/client1.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
# Now we scan the log for the DMToken and DMPubKey fields
sleep 1
while [[ $(grep "DMTOKEN:" $CLIENTOUT/client1.log) == "" ]]; do
    sleep 1
    echo -n "."
done
# Wait for a round or so for the self sent message to send
sleep 2
# Now send the DM (#2)
DMTOKEN=$(grep -a DMTOKEN $CLIENTOUT/client1.log | head -1 | awk '{print $5}')
DMPUBKEY=$(grep -a DMPUBKEY $CLIENTOUT/client1.log | head -1 | awk '{print $5}')
echo "PubKey: $DMPUBKEY, Token: $DMTOKEN"
CLIENTCMD2="timeout 360s bin/client $CLIENTDMOPTS -l $CLIENTOUT/client2.log -s blobs/2 dm -m \"Hello from Ben Prime to Rick Prime via DM\" --dmPubkey $DMPUBKEY --dmToken $DMTOKEN --receiveCount 2"
eval $CLIENTCMD2 >> $CLIENTOUT/client2.txt &
PIDVAL2=$!
echo "$CLIENTCMD2 -- $PIDVAL2"
wait $PIDVAL
# When the first command exits, read the RECVDM fields and reply to
# the last received message (the first 2 are the self send) (#3)
RTOKEN=$(grep -a RECVDMTOKEN $CLIENTOUT/client1.log | tail -1 | awk '{print $5}')
RPUBKEY=$(grep -a RECVDMPUBKEY $CLIENTOUT/client1.log | tail -1 | awk '{print $5}')
CLIENTCMD="timeout 360s bin/client $CLIENTDMOPTS -l $CLIENTOUT/client1.log -s blobs/1 dm -m \"What up from Rick Prime to Ben Prime via DM\" --dmPubkey $RPUBKEY --dmToken $RTOKEN --receiveCount 1"
eval $CLIENTCMD >> $CLIENTOUT/client1.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
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
