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

EPHREGRESULTS=$1
GOLDOUTPUT=$2
NDF=$3

DEBUGLEVEL=${DEBUGLEVEL-1}

CLIENTOUT=$EPHREGRESULTS/clients
CLIENTCLEAN=$EPHREGRESULTS/clients-cleaned

mkdir -p $CLIENTOUT
mkdir -p $CLIENTCLEAN


#export GRPC_GO_LOG_VERBOSITY_LEVEL=99
#export GRPC_GO_LOG_SEVERITY_LEVEL=info

###############################################################################
# Test Ephemeral Registration (e2e test without registering with nodes)
###############################################################################
CLIENTEPHREGOPTS="--password hello --ndf $NDF --verify-sends --sendDelay 100 --waitTimeout 360 -v $DEBUGLEVEL --disableNodeRegistration --enableImmediateSending"

echo "TESTING E2E WITH EPHEMERAL REGISTRATION"
CLIENTCMD="timeout 360s bin/client $CLIENTEPHREGOPTS -l $CLIENTOUT/client601.log -s blobs/601 --writeContact $CLIENTOUT/rick601-contact.bin --unsafe -m \"Hello from Rick601 to myself, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client601.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
CLIENTCMD="timeout 360s bin/client $CLIENTEPHREGOPTS -l $CLIENTOUT/client602.log -s blobs/602 --writeContact $CLIENTOUT/ben602-contact.bin --destfile $CLIENTOUT/rick601-contact.bin --send-auth-request --unsafe-channel-creation --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client602.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"

while [ ! -s $CLIENTOUT/ben602-contact.bin ]; do
    sleep 1
    echo -n "."
done


TMPID=$(cat $CLIENTOUT/client601.log | grep -a "User\:" | awk -F' ' '{print $5}')
RICKID=${TMPID}
echo "RICK ID: $RICKID"
TMPID=$(cat $CLIENTOUT/client602.log | grep -a "User\:" | awk -F' ' '{print $5}')
BENID=${TMPID}
echo "BEN ID: $BENID"

# Client 601 will now wait for client 602's E2E Auth channel request and confirm
CLIENTCMD="timeout 360s bin/client $CLIENTEPHREGOPTS -l $CLIENTOUT/client601.log -s blobs/601 --destfile $CLIENTOUT/ben602-contact.bin --sendCount 0 --receiveCount 0 --accept-channel --auth-timeout 360"
eval $CLIENTCMD >> $CLIENTOUT/client601.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

# Test destid syntax too, note wait for 11 messages to catch the message from above ^^^
CLIENTCMD="timeout 360s bin/client $CLIENTEPHREGOPTS -l $CLIENTOUT/client601.log -s blobs/601  --destid b64:$BENID --sendCount 5 --receiveCount 5 -m \"Hello from Rick601, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client601.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s bin/client $CLIENTEPHREGOPTS -l $CLIENTOUT/client602.log -s blobs/602  --destid b64:$RICKID --sendCount 5 --receiveCount 5 -m \"Hello from Ben602, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client602.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2
CLIENTCMD="timeout 360s bin/client $CLIENTEPHREGOPTS -l $CLIENTOUT/client601.log -s blobs/601  --destid b64:$BENID --sendCount 5 --receiveCount 5 -m \"Hello from Rick601, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client601.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s bin/client $CLIENTEPHREGOPTS -l $CLIENTOUT/client602.log -s blobs/602  --destid b64:$RICKID --sendCount 5 --receiveCount 5 -m \"Hello from Ben602, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client602.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2
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
