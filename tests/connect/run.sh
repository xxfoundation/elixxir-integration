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

########################################################################
# Test ephemeral connections
###############################################################################

CONNECTIONOPTS="--password hello --waitTimeout 360 --ndf $NDF -v $DEBUGLEVEL"

echo "TESTING EPEHMERAL CONNECTIONS..."
# Initiate server
CLIENTCMD="timeout 240s bin/client connection --ephemeral -s blobs/200 $CONNECTIONOPTS --writeContact $CLIENTOUT/client200-server.bin -l $CLIENTOUT/client200.log --startServer --serverTimeout 1m30s"
eval $CLIENTCMD > $CLIENTOUT/client200.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
echo "Sleeping to ensure connection server instantiation"
sleep 5

# Initiate client and send message to server
CLIENTCMD="timeout 240s bin/client connection --ephemeral -s blobs/201 --connect $CLIENTOUT/client200-server.bin $CONNECTIONOPTS -l $CLIENTOUT/client201.log  -m \"Hello 200 from 201, using connections\" --receiveCount 0"
eval $CLIENTCMD > $CLIENTOUT/client201.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL2
wait $PIDVAL1
echo "EPHEMERAL CONNECTION TESTS FINISHED"

###############################################################################
# Test ephemeral authenticated connections
###############################################################################
echo "TESTING EPHEMERAL AUTHENTICATED CONNECTIONS..."
# Initiate server
CLIENTCMD="timeout 240s bin/client connection --ephemeral -s blobs/202 --authenticated $CONNECTIONOPTS --writeContact $CLIENTOUT/client202-server.bin -l $CLIENTOUT/client202.log --startServer --serverTimeout 1m30s"
eval $CLIENTCMD > $CLIENTOUT/client202.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
echo "Sleeping to ensure connection server instantiation"
sleep 5

# Initiate client and send message to server
CLIENTCMD="timeout 240s bin/client connection --ephemeral -s blobs/203 --authenticated --connect $CLIENTOUT/client202-server.bin $CONNECTIONOPTS -l $CLIENTOUT/client203.log  -m \"Hello 202 from 203, using connections\" --receiveCount 0"
eval $CLIENTCMD > $CLIENTOUT/client203.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL2
wait $PIDVAL1
echo "EPHEMERAL AUTHENTICATED CONNECTION TESTS FINISHED"

###############################################################################
# Test non-ephemeral authenticated connections
###############################################################################

echo "TESTING NON-EPHEMERAL CONNECTIONS"
# Initiate server
CLIENTCMD="timeout 240s bin/client connection -s blobs/204 $CONNECTIONOPTS --writeContact $CLIENTOUT/client204-server.bin -l $CLIENTOUT/client204.log --startServer --serverTimeout 1m30s"
eval $CLIENTCMD > $CLIENTOUT/client204.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
echo "Sleeping to ensure connection server instantiation"
sleep 5

# Initiate client and send message to server
CLIENTCMD="timeout 240s bin/client connection -s blobs/205 --connect $CLIENTOUT/client204-server.bin $CONNECTIONOPTS -l $CLIENTOUT/client205.log  -m \"Hello 204 from 205, using connections\" --receiveCount 0"
eval $CLIENTCMD > $CLIENTOUT/client205.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL2
wait $PIDVAL1
echo "NON-EPHEMERAL CONNECTION TEST FINISHED."

echo "TESTING EPHEMERAL AUTHENTICATED CONNECTIONS..."
# Initiate server
CLIENTCMD="timeout 240s bin/client connection -s blobs/206 --authenticated $CONNECTIONOPTS --writeContact $CLIENTOUT/client206-server.bin -l $CLIENTOUT/client206.log --startServer --serverTimeout 1m30s"
eval $CLIENTCMD > $CLIENTOUT/client206.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
echo "Sleeping to ensure connection server instantiation"
sleep 5

# Initiate client and send message to server
CLIENTCMD="timeout 240s bin/client connection -s blobs/207 --authenticated --connect $CLIENTOUT/client206-server.bin $CONNECTIONOPTS -l $CLIENTOUT/client207.log  -m \"Hello 206 from 207, using connections\" --receiveCount 0"
eval $CLIENTCMD > $CLIENTOUT/client207.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL2
wait $PIDVAL1
echo "Non-Ephemeral Test Complete."
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
