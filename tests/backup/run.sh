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

CLIENTOPTS="--password hello --ndf $NDF --verify-sends --sendDelay 100 --waitTimeout 360 -v $DEBUGLEVEL"
CLIENTBACKUPOPTS="--password hello --ndf $NDF -v $DEBUGLEVEL"
CLIENTUDOPTS="--password hello --ndf $NDF -v $DEBUGLEVEL"

###############################################################################
# Test  Back Up & Restore
###############################################################################

echo "START BACKUP AND RESTORE..."
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client120.log -s blobs/120 --force-legacy --writeContact $CLIENTOUT/client120-contact.bin --unsafe -m \"Hello from Client120 to myself, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client120.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client121.log -s blobs/121 --force-legacy --writeContact $CLIENTOUT/client121-contact.bin --destfile $CLIENTOUT/client120-contact.bin --unsafe-channel-creation --send-auth-request --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client121.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"

while [ ! -s $CLIENTOUT/client121-contact.bin ]; do
    sleep 1
    echo -n "."
done

# Client 120 will now wait for client 121's E2E Auth channel request and confirm
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client120.log -s blobs/120 --force-legacy --destfile $CLIENTOUT/client121-contact.bin --sendCount 0 --receiveCount 0 --accept-channel --auth-timeout 360"
eval $CLIENTCMD >> $CLIENTOUT/client120.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

# Send messages to each other
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client120.log -s blobs/120 --force-legacy --destfile $CLIENTOUT/client121-contact.bin --sendCount 5 --receiveCount 5 -m \"Hello from Client120, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client120.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client121.log -s blobs/121 --force-legacy --destfile $CLIENTOUT/client120-contact.bin --sendCount 5 --receiveCount 5 -m \"Hello from Client121, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client121.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

# Register 120 with UD
CLIENTCMD="timeout 240s bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client120.log -s blobs/120 --force-legacy --register client120"
eval $CLIENTCMD >> $CLIENTOUT/client120.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

# Backup and restore 121
CLIENTCMD="timeout 60s bin/client $CLIENTBACKUPOPTS -l $CLIENTOUT/client121.log -s blobs/121 --force-legacy --backupOut $CLIENTOUT/client121A.backup --backupPass hello --backupJsonOut $CLIENTOUT/client121A.backup.json --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client121.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
echo "FIXME: The above exits uncleanly, but a backup file is created. The rest of the test fails...It should be FIXED!"
wait $PIDVAL

rm -fr blobs/121

CLIENTCMD="timeout 60s bin/client $CLIENTBACKUPOPTS -l $CLIENTOUT/client121.log -s blobs/121 --force-legacy --backupIn $CLIENTOUT/client121A.backup --backupPass hello --backupJsonOut $CLIENTOUT/client121B.backup.json --backupIdList $CLIENTOUT/client121Partners.json --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client121.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

CLIENTCMD="timeout 240s bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client121.log -s blobs/121 --force-legacy --batchadd $CLIENTOUT/client121Partners.json --unsafe-channel-creation"
eval $CLIENTCMD >> $CLIENTOUT/client121.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"

CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client120.log -s blobs/120 --force-legacy --destfile $CLIENTOUT/client121-contact.bin --sendCount 0 --receiveCount 0 --unsafe-channel-creation"
eval $CLIENTCMD >> $CLIENTOUT/client120.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL
wait $PIDVAL2

# Send messages to each other
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client120.log -s blobs/120 --force-legacy --destfile $CLIENTOUT/client121-contact.bin --sendCount 5 --receiveCount 5 -m \"Hello from Client120, with E2E Encryption after 121 restoring backup\" --unsafe-channel-creation"
eval $CLIENTCMD >> $CLIENTOUT/client120.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client121.log -s blobs/121 --force-legacy --destfile $CLIENTOUT/client120-contact.bin --sendCount 5 --receiveCount 5 -m \"Hello from Client121, with E2E Encryption after 121 restoring backup\" --unsafe-channel-creation"
eval $CLIENTCMD >> $CLIENTOUT/client121.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

# TODO: Add test that backs up and restore client 120. To do this, you need to be able to delete old requests

echo "END BACKUP AND RESTORE..."