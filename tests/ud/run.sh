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

CONNECTRESULTS=$1
GOLDOUTPUT=$2
NDF=$3

DEBUGLEVEL=${DEBUGLEVEL-1}

CLIENTOUT=$CONNECTRESULTS/clients
CLIENTCLEAN=$CONNECTRESULTS/clients-cleaned

mkdir -p $CLIENTOUT
mkdir -p $CLIENTCLEAN

#export GRPC_GO_LOG_VERBOSITY_LEVEL=99
#export GRPC_GO_LOG_SEVERITY_LEVEL=info

###############################################################################
# Test  User Discovery
###############################################################################

CLIENTUDOPTS="--password hello --ndf $NDF -v $DEBUGLEVEL"
CLIENTOPTS="--password hello --ndf $NDF --verify-sends --sendDelay 100 --waitTimeout 360 -v $DEBUGLEVEL"

# UD Test
echo "TESTING USER DISCOVERY..."
CLIENTCMD="timeout 240s bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client13.log -s blobs/13 --register josh13 --addemail josh13@elixxir.io --addphone 6178675309US"
eval $CLIENTCMD >> $CLIENTOUT/client13.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
CLIENTCMD="timeout 240s bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client31.log -s blobs/31 --register josh31 --addemail josh31@elixxir.io --addphone 6178675310US"
eval $CLIENTCMD >> $CLIENTOUT/client31.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

CLIENTCMD="timeout 240s bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client13.log -s blobs/13 --searchusername josh31 --searchemail josh31@elixxir.io --searchphone 6178675310US"
eval $CLIENTCMD > $CLIENTOUT/josh31.bin &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="timeout 240s bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client31.log -s blobs/31 --searchusername josh13 --searchemail josh13@elixxir.io --searchphone 6178675309US"
eval $CLIENTCMD > $CLIENTOUT/josh13.bin &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL1
wait $PIDVAL2

# Print IDs to console
TMPID=$(cat $CLIENTOUT/client13.log | grep -a "User\:" | awk -F' ' '{print $5}' | head -1)
UDID1=${TMPID}
echo "UD ID 1: $UDID1"
TMPID=$(cat $CLIENTOUT/client31.log | grep -a "User\:" | awk -F' ' '{print $5}' | head -1)
UDID2=${TMPID}
echo "UD ID 2: $UDID2"

# Test lookup message
CLIENTCMD="timeout 240s bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client13.log -s blobs/13 --lookup b64:$UDID2"
eval $CLIENTCMD > $CLIENTOUT/josh31.bin &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="timeout 240s bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client31.log -s blobs/31 --lookup b64:$UDID1"
eval $CLIENTCMD > $CLIENTOUT/josh13.bin &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL1
wait $PIDVAL2

# Send auth chan request
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS -l $CLIENTOUT/client13.log -s blobs/13 --destfile $CLIENTOUT/josh31.bin --send-auth-request  --unsafe-channel-creation --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client13.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"

# Approve request and confirm
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS -l $CLIENTOUT/client31.log -s blobs/31 --destfile $CLIENTOUT/josh13.bin --sendCount 0 --receiveCount 0 --accept-channel --auth-timeout 360"
eval $CLIENTCMD >> $CLIENTOUT/client31.txt &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL1
wait $PIDVAL2

# now test
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS -l $CLIENTOUT/client31.log -s blobs/31 --destfile $CLIENTOUT/josh13.bin --sendCount 5 --receiveCount 5 -m \"Hello from Josh31, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client31.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS -l $CLIENTOUT/client13.log -s blobs/13 --destfile $CLIENTOUT/josh31.bin --sendCount 5 --receiveCount 5 -m \"Hello from Josh13, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client13.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

# Test Remove User
CLIENTCMD="timeout 240s bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client13.log -s blobs/13 --remove josh13"
eval $CLIENTCMD >> $CLIENTOUT/client13.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
CLIENTCMD="timeout 240s bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client13-2.log -s blobs/13-2 --register josh13"
eval $CLIENTCMD >> $CLIENTOUT/client13-2.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
echo "NOTE: The command above causes an EXPECTED failure of unable to register!"
wait $PIDVAL

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
