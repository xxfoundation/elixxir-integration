# Client Session Tests: this script will run the "old" `client` binary to init session files and setup the environment 
# for the "new" `client-release` binary to run tests on the old session files.

set -e
#set -o xtrace

# --- Define variables to use for the test & local network ---

DEBUGLEVEL=${DEBUGLEVEL-1}
CLIENTOPTS="--password hello --ndf results/ndf.json --sendDelay 100 --waitTimeout 360 --unsafe-channel-creation -v $DEBUGLEVEL"
SERVERLOGS=results/servers
GATEWAYLOGS=results/gateways
UDBOUT=results/udb-console.txt

# --- Setup a local network ---

rm -rf client*.log blob* rick*.bin ben*.bin
rm -rf results.bak results
mkdir results

mkdir -p $SERVERLOGS
mkdir -p $GATEWAYLOGS

# Start the network
source network.sh

echo "DOWNLOADING TLS Cert..."
CMD="openssl s_client -showcerts -connect $(tr -d '[:space:]' < results/startgwserver.txt)"
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

# ------------------------------------------------------------------------------
# TESTS BEGIN BELOW
# ------------------------------------------------------------------------------

# --- Pre-canned messaging to self ---
timeout 240s ../bin/client --password hello --ndf results/ndf.json --sendDelay 100 --waitTimeout 360 --unsafe-channel-creation -v 1 -l client9-master.log --sendCount 2 --receiveCount 2 -s blob9/blob9 --sendid 9 --destid 9 -m "Hi 9->9, with E2E Encryption"
timeout 240s ../bin/client-release --force-legacy --password hello --ndf results/ndf.json --sendDelay 100 --waitTimeout 360 --unsafe-channel-creation -v 1 -l client9-release.log --sendCount 2 --receiveCount 2 -s blob9/blob9 --sendid 9 --destid 9 -m "Hi 9->9, with E2E Encryption"

# --- Messaging to another use, E2E ---

# Init storage and request an E2E channel with each other
echo "SENDING E2E MESSAGES TO NEW USERS..."
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l client42-master-init.log -s blob42 --writeContact rick42-contact.bin --unsafe -m \"Hello from Rick42 to myself, without E2E Encryption\""
eval $CLIENTCMD || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l client43-master-init.log -s blob43 --writeContact ben43-contact.bin --destfile rick42-contact.bin --send-auth-request --sendCount 0 --receiveCount 0"
eval $CLIENTCMD || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"

echo "Waiting for contact files to be created..."
while [ ! -s ben43-contact.bin ]; do
    sleep 1
done

# Get the user's IDs
TMPID=$(cat client42-master-init.log | grep -a "User\:" | awk -F' ' '{print $5}')
RICKID=${TMPID}
echo "RICK ID: $RICKID"
TMPID=$(cat client43-master-init.log | grep -a "User\:" | awk -F' ' '{print $5}')
BENID=${TMPID}
echo "BEN ID: $BENID"

# Confirm channel with each other
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l client42-master-confirm.log -s blob42 --destfile ben43-contact.bin --sendCount 0 --receiveCount 0"
eval $CLIENTCMD || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

# Send 5 messages to each other
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l client42-master-send.log -s blob42  --destid b64:$BENID --sendCount 5 --receiveCount 5 -m \"Hello from Rick42, with E2E Encryption\""
eval $CLIENTCMD || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l client43-master-send.log -s blob43  --destid b64:$RICKID --sendCount 5 --receiveCount 5 -m \"Hello from Ben43, with E2E Encryption\""
eval $CLIENTCMD || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

# Send 5 messages to each other with new client
CLIENTCMD="timeout 360s ../bin/client-release $CLIENTOPTS -l client42-release-send.log -s blob42 --force-legacy --destid b64:$BENID --sendCount 5 --receiveCount 5 -m \"Hello from Rick42, with E2E Encryption\""
eval $CLIENTCMD || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s ../bin/client-release $CLIENTOPTS -l client43-release-send.log -s blob43 --force-legacy --destid b64:$RICKID --sendCount 5 --receiveCount 5 -m \"Hello from Ben43, with E2E Encryption\""
eval $CLIENTCMD || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2
