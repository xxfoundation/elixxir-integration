
# NOTE: This is verbose on purpose.
################################################################################
## Initial Set Up & Clean Up of Past Runs
################################################################################

# Copy file into folder if it does not already exist
if [ ! -f network.sh ]; then
  cp ../network/network.sh .
fi


set -e
rm -fr results.bak || true
mv results results.bak || rm -fr results || true
rm -fr blob* || true
rm *-contact.json || true
rm server-5.qdstrm || true
rm server-5.qdrep || true

mkdir -p .elixxir

if [ $# -gt 1 ]
then
    echo "usage: $0 [gatewayip:port]"
    exit
fi


NETWORKENTRYPOINT=$1

DEBUGLEVEL=${DEBUGLEVEL-1}


SERVERLOGS=results/servers
GATEWAYLOGS=results/gateways
CLIENTOUT=results/clients
UDBOUT=results/udb-console.txt
CLIENTCLEAN=results/clients-cleaned

mkdir -p $SERVERLOGS
mkdir -p $GATEWAYLOGS
mkdir -p $CLIENTOUT
mkdir -p $CLIENTCLEAN

mkdir -p $SERVERLOGS
mkdir -p $GATEWAYLOGS
mkdir -p $CLIENTOUT
mkdir -p $CLIENTCLEAN


################################################################################
## Network Set Up
################################################################################


if [ "$NETWORKENTRYPOINT" == "betanet" ]
then
    NETWORKENTRYPOINT=$(sort -R betanet.txt | head -1)
elif [ "$NETWORKENTRYPOINT" == "mainnet" ]
then
    NETWORKENTRYPOINT=$(sort -R mainnet.txt | head -1)
elif [ "$NETWORKENTRYPOINT" == "release" ]
then
    NETWORKENTRYPOINT=$(sort -R release.txt | head -1)
elif [ "$NETWORKENTRYPOINT" == "devnet" ]
then
    NETWORKENTRYPOINT=$(sort -R devnet.txt | head -1)
elif [ "$NETWORKENTRYPOINT" == "" ]
then
    NETWORKENTRYPOINT=$(head -1 network.config)
fi

echo "NETWORK: $NETWORKENTRYPOINT"

if [ "$NETWORKENTRYPOINT" == "localhost:1060" ]
then
    source network.sh

else
    echo "Connecting to network defined at $NETWORKENTRYPOINT"
    echo $NETWORKENTRYPOINT > results/startgwserver.txt
fi

echo "localhost:1060" > results/startgwserver.txt

echo "DONE LETS DO STUFF"

echo "DOWNLOADING TLS Cert..."
# -alpn h2 added to mimic grpc headers
CMD="openssl s_client -alpn h2 -showcerts -connect $(tr -d '[:space:]' < results/startgwserver.txt)"
echo $CMD
eval $CMD < /dev/null 2>&1 > "results/startgwcert.bin"
CMD="cat results/startgwcert.bin | openssl x509 -outform PEM"
echo $CMD
eval $CMD > "results/startgwcert.pem"
head "results/startgwcert.pem"

echo "DOWNLOADING NDF..."
CLIENTCMD="../bin/client getndf --gwhost $(tr -d '[:space:]' < results/startgwserver.txt) --cert results/startgwcert.pem"
eval $CLIENTCMD >> results/ndf.json 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

cat results/ndf.json | jq . | head -5

file results/ndf.json

if [ ! -s results/ndf.json ]
then
    echo "results/ndf.json is empty, cannot proceed"
    exit -1
fi

###############################################################################
# Test Channels
###############################################################################

echo "TESTING CHANNELS..."

CLIENTOPTS="--password hello --ndf results/ndf.json --verify-sends --sendDelay 100 --waitTimeout 360 -v $DEBUGLEVEL"

# Initialize creator of channel (will use default channel file path in CLI)
CLIENTCMD="timeout 300s ../bin/client channels -s blob500 $CLIENTOPTS -l $CLIENTOUT/client500.log --receiveCount 0 --channelPath $CLIENTOUT/channel500.chan  --channelIdentityPath $CLIENTOUT/channel500.id --newChannel"
eval $CLIENTCMD > $CLIENTOUT/client500.txt 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"

wait $PIDVAL

# Have client which created channel send message to channel
CLIENTCMD="timeout 300s ../bin/client channels -s blob500 -l $CLIENTOUT/client500.log $CLIENTOPTS --receiveCount 3 --channelPath $CLIENTOUT/channel500.chan --channelIdentityPath $CLIENTOUT/channel500.id --sendToChannel --message \"Hello, channel, this is 500\""
eval $CLIENTCMD >> $CLIENTOUT/client500.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"

# Initialize client which will join channel (will use default channel file path in CLI)
CLIENTCMD="timeout 300s ../bin/client channels -s blob501 -l $CLIENTOUT/client501.log $CLIENTOPTS --receiveCount 3 --channelPath $CLIENTOUT/channel500.chan --channelIdentityPath $CLIENTOUT/channel501.id --joinChannel --sendToChannel --message \"Hello, channel, this is 501\""
eval $CLIENTCMD > $CLIENTOUT/client501.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"

# Initialize another client which will join channel (will use default channel file path in CLI)
CLIENTCMD="timeout 420s ../bin/client channels -s blob502 -l $CLIENTOUT/client502.log $CLIENTOPTS --receiveCount 3 --channelPath $CLIENTOUT/channel500.chan --channelIdentityPath $CLIENTOUT/channel502.id --joinChannel --sendToChannel --message \"Hello, channel, this is 502\""
eval $CLIENTCMD > $CLIENTOUT/client502.txt 2>&1 &
PIDVAL3=$!
echo "$CLIENTCMD -- $PIDVAL3"

wait $PIDVAL1
wait $PIDVAL2
wait $PIDVAL3

# All clients will leave the channel
CLIENTCMD="timeout 300s ../bin/client channels -s blob500 -l $CLIENTOUT/client500.log $CLIENTOPTS --receiveCount 0 --channelPath $CLIENTOUT/channel500.chan  --channelIdentityPath $CLIENTOUT/channel500.id --leaveChannel"
eval $CLIENTCMD >> $CLIENTOUT/client500.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"

CLIENTCMD="timeout 300s ../bin/client channels -s blob501 -l $CLIENTOUT/client501.log $CLIENTOPTS --receiveCount 0 --channelPath $CLIENTOUT/channel500.chan  --channelIdentityPath $CLIENTOUT/channel501.id --leaveChannel"
eval $CLIENTCMD >> $CLIENTOUT/client501.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"

# Initialize another client which will join channel (will use default channel file path in CLI)
CLIENTCMD="timeout 300s ../bin/client channels -s blob502 -l $CLIENTOUT/client502.log $CLIENTOPTS --receiveCount 0 --channelPath $CLIENTOUT/channel500.chan  --channelIdentityPath $CLIENTOUT/channel502.id --leaveChannel"
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

GOLDOUTPUT=clients.goldoutput
if [ "$NETWORKENTRYPOINT" != "localhost:1060" ]
then
    rm -fr clients.net_goldoutput || true
    GOLDOUTPUT=clients.net_goldoutput
    cp -r clients.goldoutput clients.net_goldoutput
    # Delete the localhost only files
    rm $GOLDOUTPUT/client13* || true
    rm $GOLDOUTPUT/client18* || true
    rm $GOLDOUTPUT/client19* || true
    rm $GOLDOUTPUT/client2[01]* || true
    rm $GOLDOUTPUT/client31* || true
    rm $GOLDOUTPUT/client3[56]* || true
    rm $GOLDOUTPUT/client45* || true
    rm $GOLDOUTPUT/client56* || true
    rm $GOLDOUTPUT/client67* || true
    rm $GOLDOUTPUT/client74* || true
    rm $GOLDOUTPUT/client9* || true
fi


set +x
diff -aru $GOLDOUTPUT $CLIENTCLEAN

if [ "$NETWORKENTRYPOINT" == "localhost:1060" ]
then

    #cat $CLIENTOUT/* | strings | grep -ae "ERROR" -e "FATAL" > results/client-errors || true
    #diff -ruN results/client-errors.txt noerrors.txt
    cat $SERVERLOGS/server-*.log | grep -a "ERROR" | grep -a -v "context" | grep -av "metrics" | grep -av "database" | grep -av RequestClientKey > results/server-errors.txt || true
    cat $SERVERLOGS/server-*.log | grep -a "FATAL" | grep -a -v "context" | grep -av "transport is closing" | grep -av "database" >> results/server-errors.txt || true
    diff -aruN results/server-errors.txt noerrors.txt
    IGNOREMSG="GetRoundBufferInfo: Error received: rpc error: code = Unknown desc = round buffer is empty"
    IGNORESERVE="Failed to serve "
    IGNORESTART="Failed to start "
    IGNOREREG="WARNING: MINIMUM REGISTERED NODES HAS BEEN CHANGED"
    cat $GATEWAYLOGS/*.log | grep -a "ERROR" | grep -av "context" | grep -av "certificate" | grep -av "Failed to read key" | grep -av "$IGNOREMSG" | grep -av "$IGNORESERVE" | grep -av "$IGNORESTART" | grep -av "$IGNOREREG" > results/gateway-errors.txt || true
    cat $GATEWAYLOGS/*.log | grep -a "FATAL" | grep -av "context" | grep -av "transport is closing" >> results/gateway-errors.txt || true
    diff -aruN results/gateway-errors.txt noerrors.txt
    echo "Checking backup files for equality..."
    # diff -aruN $CLIENTOUT/client120A.backup.json $CLIENTOUT/client120B.backup.json > client120BackupDiff.txt
    #diff -aruN $CLIENTOUT/client121A.backup.json $CLIENTOUT/client121B.backup.json > client121BackupDiff.txt || true
    # diff -aruN  client120BackupDiff.txt noerrors.txt
    #echo "NOTE: BACKUP CHECK DISABLED, this should be uncommented when turned back on!"
    #diff -aruN  client121BackupDiff.txt noerrors.txt
fi


# Remove the file if it exists
if [ -f network.sh ]; then
  rm network.sh
fi