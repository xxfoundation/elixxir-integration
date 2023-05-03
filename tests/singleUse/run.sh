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

SINGLERESULTS=$1
GOLDOUTPUT=$2
NDF=$3

DEBUGLEVEL=${DEBUGLEVEL-1}

CLIENTOUT=$SINGLERESULTS/clients
CLIENTCLEAN=$SINGLERESULTS/clients-cleaned

mkdir -p $CLIENTOUT
mkdir -p $CLIENTCLEAN

#export GRPC_GO_LOG_VERBOSITY_LEVEL=99
#export GRPC_GO_LOG_SEVERITY_LEVEL=info

CLIENTSINGLEOPTS="--password hello --waitTimeout 360 --ndf $NDF -v $DEBUGLEVEL"

###############################################################################
# Test  Single Use
###############################################################################

# Single-use test: client53 sends message to client52; client52 responds with
# the same message in the set number of message parts
echo "TESTING SINGLE-USE"

# Generate contact file for client52
CLIENTCMD="bin/client init -s blobs/52 -l $CLIENTOUT/client52.log --password hello --ndf results/ndf.json --writeContact $CLIENTOUT/jono52-contact.bin"
eval $CLIENTCMD >> /dev/null 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

# Start client53, which sends a message and then waits for a response
CLIENTCMD="timeout 240s bin/client single $CLIENTSINGLEOPTS -l $CLIENTOUT/client53.log -s blobs/53 --maxMessages 8 --message \"Test single-use message\" --send -c $CLIENTOUT/jono52-contact.bin --timeout 90s"
eval $CLIENTCMD >> $CLIENTOUT/client53.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"

# Start client52, which waits for a message and then responds
CLIENTCMD="timeout 240s bin/client single $CLIENTSINGLEOPTS -l $CLIENTOUT/client52.log -s blobs/52 --reply --timeout 90s"
eval $CLIENTCMD >> $CLIENTOUT/client52.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
wait $PIDVAL1
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
