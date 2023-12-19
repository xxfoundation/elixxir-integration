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

CLIENTOPTS="--password hello --ndf $NDF --verify-sends --sendDelay 100 --waitTimeout 360 -v $DEBUGLEVEL"
CLIENTREKEYOPTS="--password hello --ndf $NDF --verify-sends --waitTimeout 600 -v $DEBUGLEVEL"


###############################################################################
# Test  Rekey
###############################################################################

echo "CREATING USERS for REKEY TEST..."
JAKEID=$(bin/client init -s blobs/100 -l $CLIENTOUT/client100.log --password hello --ndf $NDF --writeContact $CLIENTOUT/Jake100-contact.bin -v $DEBUGLEVEL)
NIAMHID=$(bin/client init -s blobs/101 -l $CLIENTOUT/client101.log --password hello --ndf $NDF --writeContact $CLIENTOUT/Niamh101-contact.bin -v $DEBUGLEVEL)
echo "JAKE ID: $JAKEID"
echo "NIAMH ID: $NIAMHID"


REKEYOPTS="--e2eMaxKeys 15 --e2eMinKeys 10 --e2eNumReKeys 5 --e2eRekeyThreshold 0.75"
# Client 101 will now send auth request
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS $REKEYOPTS -l $CLIENTOUT/client101.log -s blobs/101 --writeContact $CLIENTOUT/Niamh101-contact.bin --destfile $CLIENTOUT/Jake100-contact.bin --send-auth-request --unsafe-channel-creation --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client101.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
# Client 100 will now wait for client 101's E2E Auth channel request and confirm
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS $REKEYOPTS -l $CLIENTOUT/client100.log -s blobs/100 --destid b64:$NIAMHID --sendCount 0 --receiveCount 0 --accept-channel --auth-timeout 360"
eval $CLIENTCMD >> $CLIENTOUT/client100.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

echo "RUNNING REKEY TEST..."
# Test destid syntax too, note wait for 11 messages to catch the message from above ^^^
CLIENTCMD="timeout 600s bin/client $CLIENTREKEYOPTS $REKEYOPTS -l $CLIENTOUT/client100.log -s blobs/100 --destid b64:$NIAMHID --sendCount 20 --receiveCount 20 -m \"Hello from Jake100, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client100.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 600s bin/client $CLIENTREKEYOPTS $REKEYOPTS -l $CLIENTOUT/client101.log -s blobs/101 --destid b64:$JAKEID --sendCount 20 --receiveCount 20 -m \"Hello from Niamh101, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client101.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

# Now we are just going to exhaust all the keys we have and see if we
# use the unconfirmed channels
CLIENTCMD="timeout 600s bin/client $CLIENTREKEYOPTS $REKEYOPTS -l $CLIENTOUT/client100.log -s blobs/100 --destid b64:$NIAMHID --sendCount 20 --receiveCount 0 -m \"Hello from Jake100, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client100.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
# And receive those messages sent to us
CLIENTCMD="timeout 600s bin/client $CLIENTREKEYOPTS $REKEYOPTS -l $CLIENTOUT/client101.log -s blobs/101 --destid b64:$JAKEID --sendCount 0 --receiveCount 20"
eval $CLIENTCMD >> $CLIENTOUT/client101.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2