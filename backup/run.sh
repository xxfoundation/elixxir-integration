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

if [ "$NETWORKENTRYPOINT" == "localhost:1110" ]
then
    source network.sh

else
    echo "Connecting to network defined at $NETWORKENTRYPOINT"
    echo $NETWORKENTRYPOINT > results/startgwserver.txt
fi

echo "localhost:1110" > results/startgwserver.txt

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
# Test  Back Up & Restore
###############################################################################

echo "START BACKUP AND RESTORE..."
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client120.log -s blob120 --force-legacy --writeContact $CLIENTOUT/client120-contact.bin --unsafe -m \"Hello from Client120 to myself, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client120.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client121.log -s blob121 --force-legacy --writeContact $CLIENTOUT/client121-contact.bin --destfile $CLIENTOUT/client120-contact.bin --unsafe-channel-creation --send-auth-request --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client121.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"

while [ ! -s $CLIENTOUT/client121-contact.bin ]; do
    sleep 1
    echo -n "."
done

# Client 120 will now wait for client 121's E2E Auth channel request and confirm
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client120.log -s blob120 --force-legacy --destfile $CLIENTOUT/client121-contact.bin --sendCount 0 --receiveCount 0 --accept-channel --auth-timeout 360"
eval $CLIENTCMD >> $CLIENTOUT/client120.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

# Send messages to each other
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client120.log -s blob120 --force-legacy --destfile $CLIENTOUT/client121-contact.bin --sendCount 5 --receiveCount 5 -m \"Hello from Client120, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client120.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client121.log -s blob121 --force-legacy --destfile $CLIENTOUT/client120-contact.bin --sendCount 5 --receiveCount 5 -m \"Hello from Client121, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client121.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

# Register 120 with UD
CLIENTCMD="timeout 240s ../bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client120.log -s blob120 --force-legacy --register client120"
eval $CLIENTCMD >> $CLIENTOUT/client120.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

# Backup and restore 121
CLIENTCMD="timeout 60s ../bin/client $CLIENTBACKUPOPTS -l $CLIENTOUT/client121.log -s blob121 --force-legacy --backupOut $CLIENTOUT/client121A.backup --backupPass hello --backupJsonOut $CLIENTOUT/client121A.backup.json --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client121.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
echo "FIXME: The above exits uncleanly, but a backup file is created. The rest of the test fails...It should be FIXED!"
wait $PIDVAL

rm -fr blob121

CLIENTCMD="timeout 60s ../bin/client $CLIENTBACKUPOPTS -l $CLIENTOUT/client121.log -s blob121 --force-legacy --backupIn $CLIENTOUT/client121A.backup --backupPass hello --backupJsonOut $CLIENTOUT/client121B.backup.json --backupIdList $CLIENTOUT/client121Partners.json --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client121.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

CLIENTCMD="timeout 240s ../bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client121.log -s blob121 --force-legacy --batchadd $CLIENTOUT/client121Partners.json --unsafe-channel-creation"
eval $CLIENTCMD >> $CLIENTOUT/client121.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"

CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client120.log -s blob120 --force-legacy --destfile $CLIENTOUT/client121-contact.bin --sendCount 0 --receiveCount 0 --unsafe-channel-creation"
eval $CLIENTCMD >> $CLIENTOUT/client120.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL
wait $PIDVAL2

# Send messages to each other
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client120.log -s blob120 --force-legacy --destfile $CLIENTOUT/client121-contact.bin --sendCount 5 --receiveCount 5 -m \"Hello from Client120, with E2E Encryption after 121 restoring backup\" --unsafe-channel-creation"
eval $CLIENTCMD >> $CLIENTOUT/client120.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client121.log -s blob121 --force-legacy --destfile $CLIENTOUT/client120-contact.bin --sendCount 5 --receiveCount 5 -m \"Hello from Client121, with E2E Encryption after 121 restoring backup\" --unsafe-channel-creation"
eval $CLIENTCMD >> $CLIENTOUT/client121.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

# TODO: Add test that backs up and restore client 120. To do this, you need to be able to delete old requests

echo "END BACKUP AND RESTORE..."

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

GOLDOUTPUT=clients.goldoutput
if [ "$NETWORKENTRYPOINT" != "localhost:1110" ]
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

if [ "$NETWORKENTRYPOINT" == "localhost:1110" ]
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