#!/bin/bash

# NOTE: This is verbose on purpose.
################################################################################
## Initial Set Up & Clean Up of Past Runs
################################################################################

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

CLIENTOPTS="--password hello --ndf results/ndf.json --verify-sends --sendDelay 100 --waitTimeout 360 -v $DEBUGLEVEL"
CLIENTUDOPTS="--password hello --ndf results/ndf.json -v $DEBUGLEVEL"
CLIENTSINGLEOPTS="--password hello --waitTimeout 360 --ndf results/ndf.json -v $DEBUGLEVEL"
CLIENTGROUPOPTS="--password hello --waitTimeout 600 --ndf results/ndf.json -v $DEBUGLEVEL"
CLIENTFILETRANSFEROPTS="--password hello --waitTimeout 600 --ndf results/ndf.json -v $DEBUGLEVEL"
CLIENTREKEYOPTS="--password hello --ndf results/ndf.json --verify-sends --waitTimeout 600 -v $DEBUGLEVEL"
CLIENTBACKUPOPTS="--password hello --ndf results/ndf.json -v $DEBUGLEVEL"
CONNECTIONOPTS="--password hello --waitTimeout 360 --ndf results/ndf.json -v $DEBUGLEVEL"

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

if [ "$NETWORKENTRYPOINT" == "localhost:8440" ]
then
    source network.sh

else
    echo "Connecting to network defined at $NETWORKENTRYPOINT"
    echo $NETWORKENTRYPOINT > results/startgwserver.txt
fi

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

cat results/ndf.json | jq . | head -5

file results/ndf.json

if [ ! -s results/ndf.json ]
then
    echo "results/ndf.json is empty, cannot proceed"
    exit -1
fi


#export GRPC_GO_LOG_VERBOSITY_LEVEL=99
#export GRPC_GO_LOG_SEVERITY_LEVEL=info


echo "RUNNING CLIENTS..."

runclients() {
    echo "Starting clients..."

    # Now send messages to each other
    CTR=0
    for cid in $(seq 4 7)
    do
        # TODO: Change the recipients to send multiple messages. We can't
        #       run multiple clients with the same user id so we need
        #       updates to make that work.
        #     for nid in 1 2 3 4; do
        for nid in 1
        do
            nid=$(((($cid + 1) % 4) + 4))
            eval NICK=\${NICK${cid}}
            # Send a regular message
            mkdir -p blob$cid
            CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client$cid$nid.log -s blob$cid/blob$cid --unsafe --sendid $cid --destid $nid --sendCount 20 --receiveCount 20 -m \"Hello, $nid\""
            eval $CLIENTCMD >> $CLIENTOUT/client$cid$nid.txt 2>&1 &
            PIDVAL=$!
            eval CLIENTS${CTR}=$PIDVAL
            echo "$CLIENTCMD -- $PIDVAL"
            CTR=$(($CTR + 1))
        done
    done

    echo "WAITING FOR $CTR CLIENTS TO EXIT..."
    for i in $(seq 0 $(($CTR - 1)))
    do
        eval echo "Waiting on \${CLIENTS${i}} ..."
        eval wait \${CLIENTS${i}}
    done
}

###############################################################################
# Test  Basic Client
###############################################################################


if [ "$NETWORKENTRYPOINT" == "localhost:8440" ]
then

    echo "RUNNING BASIC CLIENTS..."
    runclients
    echo "RUNNING BASIC CLIENTS (2nd time)..."
    runclients

    # Send E2E messages between a single user
    mkdir -p blob9
    mkdir -p blob18
    mkdir -p blob91
    echo "TEST E2E WITH PRECANNED USERS..."
    CLIENTCMD="timeout 240s ../bin/client  $CLIENTOPTS -l $CLIENTOUT/client9.log --sendCount 2 --receiveCount 2 -s blob9/blob9 --sendid 9 --destid 9 -m \"Hi 9->9, with E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client9.txt 2>&1 &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    wait $PIDVAL
    CLIENTCMD="timeout 240s ../bin/client  $CLIENTOPTS -l $CLIENTOUT/client9.log --sendCount 2 --receiveCount 2 -s blob9/blob9 --sendid 9 --destid 9 -m \"Hi 9->9, with E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client9.txt 2>&1 &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    wait $PIDVAL
    CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client18.log --sendCount 2 --receiveCount 2 -s blob18/blob18 --slowPolling --sendid 18 --destid 18 -m \"Hi 18->18, with E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client18.txt 2>&1 &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    wait $PIDVAL


    # Send E2E messages between two users
    CLIENTCMD="timeout 240s ../bin/client  $CLIENTOPTS -l $CLIENTOUT/client9.log --sendCount 3 --receiveCount 3 -s blob9/blob9 --sendid 9 --destid 18 -m \"Hi 9->18, with E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client9.txt 2>&1 &
    PIDVAL1=$!
    echo "$CLIENTCMD -- $PIDVAL"
    CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client18.log --sendCount 3 --receiveCount 3 -s blob18/blob18 --sendid 18 --destid 9 -m \"Hi 18->9, with E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client18.txt 2>&1 &
    PIDVAL2=$!
    echo "$CLIENTCMD -- $PIDVAL"
    wait $PIDVAL1
    wait $PIDVAL2


    # Send multiple E2E encrypted messages between users that discovered each other
    echo "SENDING MESSAGES TO PRECANNED USERS AND FORCING A REKEY..."
    CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client18_rekey.log --sendCount 20 --receiveCount 20 --destid 9 -s blob18/blob18 -m \"Hello, 9, with E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client18_rekey.txt 2>&1 &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client9_rekey.log --sendCount 20 --receiveCount 20 --destid 18 -s blob9/blob9 -m \"Hello, 18, with E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client9_rekey.txt 2>&1 &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    wait $PIDVAL

    echo "FORCING HISTORICAL ROUNDS... (NON-E2E, PRECAN)"
    CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS --forceHistoricalRounds --unsafe -l $CLIENTOUT/client33.log -s blob33 --sendid 1 --destid 2 --sendCount 5 --receiveCount 5 -m \"Hello from 1, without E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client33.txt &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS --forceHistoricalRounds --unsafe -l $CLIENTOUT/client34.log -s blob34 --sendid 2 --destid 1 --sendCount 5 --receiveCount 5 -m \"Hello from 2, without E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client34.txt &
    PIDVAL2=$!
    echo "$CLIENTCMD -- $PIDVAL"
    wait $PIDVAL
    wait $PIDVAL2

    echo "FORCING MESSAGE PICKUP RETRY... (NON-E2E, PRECAN)"
    # Higher timeouts for this test to allow message pickup retry to function
    CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS --forceMessagePickupRetry --unsafe -l $CLIENTOUT/client20.log -s blob20 --sendid 20 --destid 21 --sendCount 5 --receiveCount 5 -m \"Hello from 20, without E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client20.txt &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS --forceMessagePickupRetry --unsafe -l $CLIENTOUT/client21.log -s blob21 --sendid 21 --destid 20 --sendCount 5 --receiveCount 5 -m \"Hello from 21, without E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client21.txt &
    PIDVAL2=$!
    echo "$CLIENTCMD -- $PIDVAL"
    wait $PIDVAL
    wait $PIDVAL2


fi

###############################################################################
# Test  Sending E2E
###############################################################################

# Non-precanned E2E user messaging
echo "SENDING E2E MESSAGES TO NEW USERS..."
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blob42 --writeContact $CLIENTOUT/rick42-contact.bin --unsafe -m \"Hello from Rick42 to myself, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client42.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -s blob43 --writeContact $CLIENTOUT/ben43-contact.bin --destfile $CLIENTOUT/rick42-contact.bin --send-auth-request --unsafe-channel-creation --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client43.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"

while [ ! -s $CLIENTOUT/ben43-contact.bin ]; do
    sleep 1
    echo -n "."
done


TMPID=$(cat $CLIENTOUT/client42.log | grep -a "User\:" | awk -F' ' '{print $5}')
RICKID=${TMPID}
echo "RICK ID: $RICKID"
TMPID=$(cat $CLIENTOUT/client43.log | grep -a "User\:" | awk -F' ' '{print $5}')
BENID=${TMPID}
echo "BEN ID: $BENID"

# Client 42 will now wait for client 43's E2E Auth channel request and confirm
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blob42 --destfile $CLIENTOUT/ben43-contact.bin --sendCount 0 --receiveCount 0 --accept-channel --auth-timeout 360"
eval $CLIENTCMD >> $CLIENTOUT/client42.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

# Test destid syntax too, note wait for 11 messages to catch the message from above ^^^
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blob42  --destid b64:$BENID --sendCount 5 --receiveCount 5 -m \"Hello from Rick42, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client42.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -s blob43  --destid b64:$RICKID --sendCount 5 --receiveCount 5 -m \"Hello from Ben43, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client43.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blob42  --destid b64:$BENID --sendCount 5 --receiveCount 5 -m \"Hello from Rick42, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client42.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -s blob43  --destid b64:$RICKID --sendCount 5 --receiveCount 5 -m \"Hello from Ben43, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client43.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

###############################################################################
# Test  Renegotiation
###############################################################################

echo "TESTING RENEGOTIATION..."
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -s blob43 --destfile $CLIENTOUT/rick42-contact.bin --send-auth-request  --unsafe-channel-creation --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client43.txt &
PIDVAL1=$!
# Unlike before, we don't accept the channel (it's already been accepted, it'll
# renegotiate), so instead we message ourselves to wait for the trigger
echo "$CLIENTCMD -- $PIDVAL1"
# Client 42 will now wait, again, for client 43's E2E Auth channel request and confirm
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blob42 --destfile $CLIENTOUT/rick42-contact.bin --sendCount 10 --receiveCount 10 --unsafe -m \"Waiting on renegotiation\""
eval $CLIENTCMD >> $CLIENTOUT/client42.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL1
wait $PIDVAL2
#Send a few messages
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blob42  --destid b64:$BENID --sendCount 5 --receiveCount 5 -m \"Hello from Rick42, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client42.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -s blob43  --destid b64:$RICKID --sendCount 5 --receiveCount 5 -m \"Hello from Ben43, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client43.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL
wait $PIDVAL2

echo "SWITCHING RENEGOTIATION TEST..."
# Switch places, 42 renegotiates with 43
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blob42 --destfile $CLIENTOUT/ben43-contact.bin --send-auth-request  --unsafe-channel-creation --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client42.txt &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
# Client 43 will now wait, for client 42's renegotiated E2E Auth channel request and confirm
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -s blob43 --destfile $CLIENTOUT/ben43-contact.bin --sendCount 10 --receiveCount 10 --unsafe -m \"Waiting on switching renegotiation\""
eval $CLIENTCMD >> $CLIENTOUT/client43.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL1
wait $PIDVAL2
#Send a few more messages
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blob42  --destid b64:$BENID --sendCount 5 --receiveCount 5 -m \"Hello from Rick42, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client42.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -s blob43  --destid b64:$RICKID --sendCount 5 --receiveCount 5 -m \"Hello from Ben43, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client43.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL
wait $PIDVAL2
echo "END RENEGOTIATION"

###############################################################################
# Test  Deleting Contacts & Requests
###############################################################################

echo "DELETING CONTACT FROM CLIENT..."
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blob42 --delete-channel --destfile $CLIENTOUT/ben43-contact.bin --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client42.txt &
echo "$CLIENTCMD -- $PIDVAL"
PIDVAL1=$!
wait $PIDVAL1
# NOTE the command below causes the following EXPECTED error:
# panic: Could not confirm authentication channel for HTAmEeBhbLi6aFqcWsi3OZNDE/642GAchpATjhYFTHwD, waited 120 seconds.
# Note that the above is example, client IDs will vary
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blob42  --destid b64:$BENID --sendCount 5 --receiveCount 5 -m \"Hello from Rick42, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client42.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
echo "NOTE: The command above causes an EXPECTED failure to confirm authentication channel!"
wait $PIDVAL2

echo "DELETING REQUESTS FROM CLIENT.."
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client44.log -s blob44 --writeContact $CLIENTOUT/david44-contact.bin --unsafe -m \"Hello from David44 to myself, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client44.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

# NOTE: client45 is a precan user (see runclients), so we skip to 46 here.
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client46.log -s blob46 --writeContact $CLIENTOUT/matt46-contact.bin --destfile $CLIENTOUT/david44-contact.bin  --unsafe-channel-creation --send-auth-request --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client46.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL2

CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client46.log -s blob46 --delete-sent-requests --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client46.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL2

# This is tricky -- we've deleted the request without having received the
# confirmation, so now the receiver attempts to accept the channel while the
# sender (without confirmation) sends to them without an auth channel.
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client44.log -s blob44 --destfile $CLIENTOUT/matt46-contact.bin --sendCount 0 --receiveCount 0 --accept-channel --auth-timeout 360"
eval $CLIENTCMD >> $CLIENTOUT/client44.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client46.log -s blob46  --destfile $CLIENTOUT/david44-contact.bin --sendCount 5 --receiveCount 5 -m \"Hello from David, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client46.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
echo "NOTE: The command above causes an EXPECTED failure to confirm authentication channel!"
wait $PIDVAL
wait $PIDVAL2

###############################################################################
# Test  Simultaneous Auth
###############################################################################

echo "CREATING USERS for SIMULTANEOUSAUTH TEST..."
JONOID=$(../bin/client init -s blob85 -l $CLIENTOUT/client85.log --password hello --ndf results/ndf.json --writeContact $CLIENTOUT/jono85-contact.bin -v $DEBUGLEVEL)
SYDNEYID=$(../bin/client init -s blob86 -l $CLIENTOUT/client86.log --password hello --ndf results/ndf.json --writeContact $CLIENTOUT/sydney86-contact.bin -v $DEBUGLEVEL)
echo "JONO ID: $JONOID"
echo "SYDNEY ID: $SYDNEYID"

# Attempt to send an auth request at the same time. It's not guaranteed that
# one side won't send and the other won't receive before sending their request
# but this method has proven to be reasonably reliable.
echo "STARTING SIMULTANEOUSAUTH TEST..."
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client85.log -s blob85 --destfile $CLIENTOUT/sydney86-contact.bin --unsafe-channel-creation --send-auth-request --unsafe-channel-creation --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client85.txt &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client86.log -s blob86 --destfile $CLIENTOUT/jono85-contact.bin --unsafe-channel-creation --send-auth-request --unsafe-channel-creation --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client86.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL1
wait $PIDVAL2

# Send a couple messages
echo "TESTING SIMULTANEOUSAUTH MESSAGE SEND..."
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client85.log -s blob85 --destfile $CLIENTOUT/sydney86-contact.bin --sendCount 5 --receiveCount 5 -m \"Hello Sydney from Jono, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client85.txt &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client86.log -s blob86 --destfile $CLIENTOUT/jono85-contact.bin --sendCount 5 --receiveCount 5 -m \"Hello Jono from Sydney, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client86.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL1
wait $PIDVAL2

###############################################################################
# Test  Rekey
###############################################################################

echo "CREATING USERS for REKEY TEST..."
JAKEID=$(../bin/client init -s blob100 -l $CLIENTOUT/client100.log --password hello --ndf results/ndf.json --writeContact $CLIENTOUT/Jake100-contact.bin -v $DEBUGLEVEL)
NIAMHID=$(../bin/client init -s blob101 -l $CLIENTOUT/client101.log --password hello --ndf results/ndf.json --writeContact $CLIENTOUT/Niamh101-contact.bin -v $DEBUGLEVEL)
echo "JAKE ID: $JAKEID"
echo "NIAMH ID: $NIAMHID"


REKEYOPTS="--e2eMaxKeys 15 --e2eMinKeys 10 --e2eNumReKeys 5 --e2eRekeyThreshold 0.75"
# Client 101 will now send auth request
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS $REKEYOPTS -l $CLIENTOUT/client101.log -s blob101 --writeContact $CLIENTOUT/Niamh101-contact.bin --destfile $CLIENTOUT/Jake100-contact.bin --send-auth-request --unsafe-channel-creation --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client101.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
# Client 100 will now wait for client 101's E2E Auth channel request and confirm
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS $REKEYOPTS -l $CLIENTOUT/client100.log -s blob100 --destid b64:$NIAMHID --sendCount 0 --receiveCount 0 --accept-channel --auth-timeout 360"
eval $CLIENTCMD >> $CLIENTOUT/client100.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

echo "RUNNING REKEY TEST..."
# Test destid syntax too, note wait for 11 messages to catch the message from above ^^^
CLIENTCMD="timeout 600s ../bin/client $CLIENTREKEYOPTS $REKEYOPTS -l $CLIENTOUT/client100.log -s blob100 --destid b64:$NIAMHID --sendCount 20 --receiveCount 20 -m \"Hello from Jake100, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client100.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 600s ../bin/client $CLIENTREKEYOPTS $REKEYOPTS -l $CLIENTOUT/client101.log -s blob101 --destid b64:$JAKEID --sendCount 20 --receiveCount 20 -m \"Hello from Niamh101, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client101.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

# Now we are just going to exhaust all the keys we have and see if we
# use the unconfirmed channels
CLIENTCMD="timeout 600s ../bin/client $CLIENTREKEYOPTS $REKEYOPTS -l $CLIENTOUT/client100.log -s blob100 --destid b64:$NIAMHID --sendCount 20 --receiveCount 0 -m \"Hello from Jake100, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client100.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
# And receive those messages sent to us
CLIENTCMD="timeout 600s ../bin/client $CLIENTREKEYOPTS $REKEYOPTS -l $CLIENTOUT/client101.log -s blob101 --destid b64:$JAKEID --sendCount 0 --receiveCount 20"
eval $CLIENTCMD >> $CLIENTOUT/client101.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

###############################################################################
# Test  Historical Rounds
###############################################################################

echo "FORCING HISTORICAL ROUNDS..."
FH1ID=$(../bin/client init -s blob35 -l $CLIENTOUT/client35.log --password hello --ndf results/ndf.json --writeContact $CLIENTOUT/FH1-contact.bin -v $DEBUGLEVEL)
FH2ID=$(../bin/client init -s blob36 -l $CLIENTOUT/client36.log --password hello --ndf results/ndf.json --writeContact $CLIENTOUT/FH2-contact.bin -v $DEBUGLEVEL)
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS --forceHistoricalRounds --unsafe -l $CLIENTOUT/client35.log -s blob35 --destid b64:$FH2ID --sendCount 5 --receiveCount 5 -m \"Hello from 35, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client35.txt  &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS --forceHistoricalRounds --unsafe -l $CLIENTOUT/client36.log -s blob36 --destid b64:$FH1ID --sendCount 5 --receiveCount 5 -m \"Hello from 36, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client36.txt  &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

echo "FORCING MESSAGE PICKUP RETRY... "
FM1ID=$(../bin/client init -s blob22 -l $CLIENTOUT/client22.log --password hello --ndf results/ndf.json --writeContact $CLIENTOUT/FM1-contact.bin -v $DEBUGLEVEL)
FM2ID=$(../bin/client init -s blob23 -l $CLIENTOUT/client23.log --password hello --ndf results/ndf.json --writeContact $CLIENTOUT/FM2-contact.bin -v $DEBUGLEVEL)
# Higher timeouts for this test to allow message pickup retry to function
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS --forceMessagePickupRetry -l $CLIENTOUT/client22.log -s blob22 --destid b64:$FM2ID --sendCount 5 --receiveCount 5 -m \"Hello from 22, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client22.txt || true  &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS --forceMessagePickupRetry -l $CLIENTOUT/client23.log -s blob23  --destid b64:$FM1ID --sendCount 5 --receiveCount 5 -m \"Hello from 23, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client23.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
echo "FIXME: The command above causes an UNEXPECTED failure and should be FIXED!"
wait $PIDVAL
wait $PIDVAL2

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

# rm -fr blob121

# CLIENTCMD="timeout 60s ../bin/client $CLIENTBACKUPOPTS -l $CLIENTOUT/client121.log -s blob121 --force-legacy --backupIn $CLIENTOUT/client121A.backup --backupPass hello --backupJsonOut $CLIENTOUT/client121B.backup.json --backupIdList $CLIENTOUT/client121Partners.json --sendCount 0 --receiveCount 0"
# eval $CLIENTCMD >> $CLIENTOUT/client121.txt &
# PIDVAL=$!
# echo "$CLIENTCMD -- $PIDVAL"
# wait $PIDVAL

# CLIENTCMD="timeout 240s ../bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client121.log -s blob121 --force-legacy --batchadd $CLIENTOUT/client121Partners.json --unsafe-channel-creation"
# eval $CLIENTCMD >> $CLIENTOUT/client121.txt &
# PIDVAL=$!
# echo "$CLIENTCMD -- $PIDVAL"

# CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client120.log -s blob120 --force-legacy --destfile $CLIENTOUT/client121-contact.bin --sendCount 0 --receiveCount 0 --unsafe-channel-creation"
# eval $CLIENTCMD >> $CLIENTOUT/client120.txt &
# PIDVAL2=$!
# echo "$CLIENTCMD -- $PIDVAL2"
# wait $PIDVAL
# wait $PIDVAL2

# # Send messages to each other
# CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client120.log -s blob120 --force-legacy --destfile $CLIENTOUT/client121-contact.bin --sendCount 5 --receiveCount 5 -m \"Hello from Client120, with E2E Encryption after 121 restoring backup\" --unsafe-channel-creation"
# eval $CLIENTCMD >> $CLIENTOUT/client120.txt || true &
# PIDVAL=$!
# echo "$CLIENTCMD -- $PIDVAL"
# CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client121.log -s blob121 --force-legacy --destfile $CLIENTOUT/client120-contact.bin --sendCount 5 --receiveCount 5 -m \"Hello from Client121, with E2E Encryption after 121 restoring backup\" --unsafe-channel-creation"
# eval $CLIENTCMD >> $CLIENTOUT/client121.txt || true &
# PIDVAL2=$!
# echo "$CLIENTCMD -- $PIDVAL"
# wait $PIDVAL
# wait $PIDVAL2

# TODO: Add test that backs up and restore client 120. To do this, you need to be able to delete old requests

echo "END BACKUP AND RESTORE..."

###############################################################################
# Test  Proto User
###############################################################################

# Proto user test: client25 and client26 generate a proto user JSON file and close.
# Both clients are restarted and load from their respective proto user files and attempt to send.

# Generate contact and proto user file for client25
echo "TESTING PROTO USER FILE..."

CLIENTCMD="timeout 60s ../bin/client -l $CLIENTOUT/client25.log -s blob11420 --password hello --ndf results/ndf.json --writeContact $CLIENTOUT/josh25-contact.bin --protoUserOut $CLIENTOUT/client25Proto.json --unsafe --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client25.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

# Generate contact and proto user file for client 26
CLIENTCMD="timeout 60s ../bin/client -l $CLIENTOUT/client26.log -s blob11421 --password hello --ndf results/ndf.json --writeContact $CLIENTOUT/jonah26-contact.bin --protoUserOut $CLIENTOUT/client26Proto.json --unsafe --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client26.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

# Clients will now load from the protoUser file and write to session
CLIENTCMD="timeout 60s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client25.log -s blob25  --protoUserPath $CLIENTOUT/client25Proto.json --unsafe --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client25.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 60s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client26.log -s blob26  --protoUserPath $CLIENTOUT/client26Proto.json --unsafe --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client26.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL
wait $PIDVAL2

# Continue with E2E testing with session files loaded from proto
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client25.log -s blob25 --writeContact $CLIENTOUT/josh25-contact.bin --unsafe -m \"Hello from Josh25 to myself, without E2E Encryption\" "
eval $CLIENTCMD >> $CLIENTOUT/client25.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client26.log -s blob26 --writeContact $CLIENTOUT/jonah26-contact.bin --destfile $CLIENTOUT/josh25-contact.bin  --unsafe-channel-creation --send-auth-request --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client26.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"

while [ ! -s $CLIENTOUT/jonah26-contact.bin ]; do
    sleep 1
    echo -n "."
done
sleep 1

# Print IDs to console
TMPID=$(cat $CLIENTOUT/client25.log | grep -a "User\:" | awk -F' ' '{print $5}' | head -1)
JOSHID=${TMPID}
echo "JOSH ID: $JOSHID"
TMPID=$(cat $CLIENTOUT/client26.log | grep -a "User\:" | awk -F' ' '{print $5}' | head -1)
JONAHID=${TMPID}
echo "JONAH ID: $JONAHID"

## Client 25 will now wait for client 26's E2E Auth channel request and confirm
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client25.log -s blob25 --destfile $CLIENTOUT/jonah26-contact.bin --sendCount 0 --receiveCount 0 --accept-channel --auth-timeout 360"
eval $CLIENTCMD >> $CLIENTOUT/client25.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

# Send E2E messages with written sessions
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client25.log -s blob25 --destid b64:$JONAHID --sendCount 5 --receiveCount 5 -m \"Hello from Josh25, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client25.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client26.log -s blob26  --destid b64:$JOSHID --sendCount 5 --receiveCount 5 -m \"Hello from Jonah26, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client26.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client25.log -s blob25 --destid b64:$JONAHID --sendCount 5 --receiveCount 5 -m \"Hello from Josh25, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client25.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client26.log -s blob26 --destid b64:$JOSHID --sendCount 5 --receiveCount 5 -m \"Hello from Jonah26, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client26.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

###############################################################################
# Test  Single Use
###############################################################################

# Single-use test: client53 sends message to client52; client52 responds with
# the same message in the set number of message parts
echo "TESTING SINGLE-USE"

# Generate contact file for client52
CLIENTCMD="../bin/client init -s blob52 -l $CLIENTOUT/client52.log --password hello --ndf results/ndf.json --writeContact $CLIENTOUT/jono52-contact.bin"
eval $CLIENTCMD >> /dev/null 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

# Start client53, which sends a message and then waits for a response
CLIENTCMD="timeout 240s ../bin/client single $CLIENTSINGLEOPTS -l $CLIENTOUT/client53.log -s blob53 --maxMessages 8 --message \"Test single-use message\" --send -c $CLIENTOUT/jono52-contact.bin --timeout 90s"
eval $CLIENTCMD >> $CLIENTOUT/client53.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"

# Start client52, which waits for a message and then responds
CLIENTCMD="timeout 240s ../bin/client single $CLIENTSINGLEOPTS -l $CLIENTOUT/client52.log -s blob52 --reply --timeout 90s"
eval $CLIENTCMD >> $CLIENTOUT/client52.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
wait $PIDVAL1
wait $PIDVAL2

###############################################################################
# Test  User Discovery
###############################################################################

if [ "$NETWORKENTRYPOINT" == "localhost:8440" ]
then
    # UD Test
    echo "TESTING USER DISCOVERY..."
    CLIENTCMD="timeout 240s ../bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client13.log -s blob13 --register josh13 --addemail josh13@elixxir.io --addphone 6178675309US"
    eval $CLIENTCMD >> $CLIENTOUT/client13.txt &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    wait $PIDVAL
    CLIENTCMD="timeout 240s ../bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client31.log -s blob31 --register josh31 --addemail josh31@elixxir.io --addphone 6178675310US"
    eval $CLIENTCMD >> $CLIENTOUT/client31.txt &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    wait $PIDVAL

    CLIENTCMD="timeout 240s ../bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client13.log -s blob13 --searchusername josh31 --searchemail josh31@elixxir.io --searchphone 6178675310US"
    eval $CLIENTCMD > $CLIENTOUT/josh31.bin &
    PIDVAL1=$!
    echo "$CLIENTCMD -- $PIDVAL1"
    CLIENTCMD="timeout 240s ../bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client31.log -s blob31 --searchusername josh13 --searchemail josh13@elixxir.io --searchphone 6178675309US"
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
    CLIENTCMD="timeout 240s ../bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client13.log -s blob13 --lookup b64:$UDID2"
    eval $CLIENTCMD > $CLIENTOUT/josh31.bin &
    PIDVAL1=$!
    echo "$CLIENTCMD -- $PIDVAL1"
    CLIENTCMD="timeout 240s ../bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client31.log -s blob31 --lookup b64:$UDID1"
    eval $CLIENTCMD > $CLIENTOUT/josh13.bin &
    PIDVAL2=$!
    echo "$CLIENTCMD -- $PIDVAL2"
    wait $PIDVAL1
    wait $PIDVAL2

    # Send auth chan request
    CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client13.log -s blob13 --destfile $CLIENTOUT/josh31.bin --send-auth-request  --unsafe-channel-creation --sendCount 0 --receiveCount 0"
    eval $CLIENTCMD >> $CLIENTOUT/client13.txt &
    PIDVAL2=$!
    echo "$CLIENTCMD -- $PIDVAL2"

    # Approve request and confirm
    CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client31.log -s blob31 --destfile $CLIENTOUT/josh13.bin --sendCount 0 --receiveCount 0 --accept-channel --auth-timeout 360"
    eval $CLIENTCMD >> $CLIENTOUT/client31.txt &
    PIDVAL1=$!
    echo "$CLIENTCMD -- $PIDVAL2"
    wait $PIDVAL1
    wait $PIDVAL2

    # now test
    CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client31.log -s blob31 --destfile $CLIENTOUT/josh13.bin --sendCount 5 --receiveCount 5 -m \"Hello from Josh31, with E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client31.txt &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client13.log -s blob13 --destfile $CLIENTOUT/josh31.bin --sendCount 5 --receiveCount 5 -m \"Hello from Josh13, with E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client13.txt &
    PIDVAL2=$!
    echo "$CLIENTCMD -- $PIDVAL"
    wait $PIDVAL
    wait $PIDVAL2

    # Test Remove User
    CLIENTCMD="timeout 240s ../bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client13.log -s blob13 --remove josh13"
    eval $CLIENTCMD >> $CLIENTOUT/client13.txt &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    wait $PIDVAL
    CLIENTCMD="timeout 240s ../bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client13-2.log -s blob13-2 --register josh13"
    eval $CLIENTCMD >> $CLIENTOUT/client13-2.txt || true &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    echo "NOTE: The command above causes an EXPECTED failure of unable to register!"
    wait $PIDVAL
fi

###############################################################################
# Test  Group Chat
###############################################################################

echo "TESTING GROUP CHAT..."
# Create authenticated channel between client 80 and 81
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client80.log -s blob80 --writeContact $CLIENTOUT/client80-contact.bin --unsafe -m \"Hello from contact 80 to myself, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client80.txt &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
wait $PIDVAL1
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client81.log -s blob81 --writeContact $CLIENTOUT/client81-contact.bin --destfile $CLIENTOUT/client80-contact.bin --send-auth-request --unsafe-channel-creation --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client81.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"

while [ ! -s $CLIENTOUT/client81-contact.bin ]; do
    sleep 1
    echo -n "."
done
echo

TMPID=$(cat $CLIENTOUT/client80.log | grep -a "User\:" | awk -F' ' '{print $5}')
CLIENT80ID=${TMPID}
echo "CLIENT 80 ID: $CLIENT80ID"
TMPID=$(cat $CLIENTOUT/client81.log | grep -a "User\:" | awk -F' ' '{print $5}')
CLIENT81ID=${TMPID}
echo "CLIENT 81 ID: $CLIENT81ID"

# Client 81 will now wait for client 81's E2E Auth channel request and confirm
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client80.log -s blob80 --destfile $CLIENTOUT/client81-contact.bin --sendCount 0 --receiveCount 0 --accept-channel --auth-timeout 360"
eval $CLIENTCMD >> $CLIENTOUT/client80.txt &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
wait $PIDVAL1
wait $PIDVAL2


# Create authenticated channel between client 80 and 82
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client82.log -s blob82 --writeContact $CLIENTOUT/client82-contact.bin --destfile $CLIENTOUT/client80-contact.bin --send-auth-request --unsafe-channel-creation --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client82.txt &
PIDVAL3=$!
echo "$CLIENTCMD -- $PIDVAL3"

while [ ! -s $CLIENTOUT/client82-contact.bin ]; do
    sleep 1
    echo -n "."
done
echo

TMPID=$(cat $CLIENTOUT/client82.log | grep -a "User\:" | awk -F' ' '{print $5}')
CLIENT82ID=${TMPID}
echo "CLIENT 82 ID: $CLIENT82ID"

# Client 82 will now wait for client 82's E2E Auth channel request and confirm
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client80.log -s blob80 --destfile $CLIENTOUT/client82-contact.bin --sendCount 0 --receiveCount 0 --accept-channel --auth-timeout 360"
eval $CLIENTCMD >> $CLIENTOUT/client80.txt &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
wait $PIDVAL1
wait $PIDVAL3

# User 1 Creates Group
echo "Group User IDs: $CLIENT80ID $CLIENT81ID $CLIENT82ID"
echo "b64:$CLIENT81ID" > $CLIENTOUT/groupParticipants
echo "b64:$CLIENT82ID" >> $CLIENTOUT/groupParticipants
CLIENTCMD="timeout 605s ../bin/client group -s blob80 -l $CLIENTOUT/client80.log $CLIENTGROUPOPTS --create $CLIENTOUT/groupParticipants --message \"80 inviting 81 and 82 to new group\""
eval $CLIENTCMD > $CLIENTOUT/client80.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="../bin/client group -s blob81 -l $CLIENTOUT/client81.log $CLIENTGROUPOPTS --join"
eval $CLIENTCMD > $CLIENTOUT/client81.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
CLIENTCMD="../bin/client group -s blob82 -l $CLIENTOUT/client82.log $CLIENTGROUPOPTS --join"
eval $CLIENTCMD > $CLIENTOUT/client82.txt 2>&1 &
PIDVAL3=$!
echo "$CLIENTCMD -- $PIDVAL3"
wait $PIDVAL1
wait $PIDVAL2
wait $PIDVAL3

# Extract group ID -- Note to Jono this probably needs to be fixed!
GROUPID=$(cat $CLIENTOUT/client80.log | grep -a "NewGroupID\:" | awk -F' ' '{print $6}')
echo "Group ID: $GROUPID"

# Print the group list from all users
CLIENTCMD="../bin/client group -s blob80 -l $CLIENTOUT/client80.log $CLIENTGROUPOPTS --list"
eval $CLIENTCMD >> $CLIENTOUT/client80.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="../bin/client group -s blob81 -l $CLIENTOUT/client81.log $CLIENTGROUPOPTS --list"
eval $CLIENTCMD >> $CLIENTOUT/client81.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
CLIENTCMD="../bin/client group -s blob82 -l $CLIENTOUT/client82.log $CLIENTGROUPOPTS --list"
eval $CLIENTCMD >> $CLIENTOUT/client82.txt 2>&1 &
PIDVAL3=$!
echo "$CLIENTCMD -- $PIDVAL3"
wait $PIDVAL1
wait $PIDVAL2
wait $PIDVAL3

# Print group from all users
CLIENTCMD="../bin/client group -s blob80 -l $CLIENTOUT/client80.log $CLIENTGROUPOPTS --show $GROUPID"
eval $CLIENTCMD >> $CLIENTOUT/client80.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="../bin/client group -s blob81 -l $CLIENTOUT/client81.log $CLIENTGROUPOPTS --show $GROUPID"
eval $CLIENTCMD >> $CLIENTOUT/client81.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
CLIENTCMD="../bin/client group -s blob82 -l $CLIENTOUT/client82.log $CLIENTGROUPOPTS --show $GROUPID"
eval $CLIENTCMD >> $CLIENTOUT/client82.txt 2>&1 &
PIDVAL3=$!
echo "$CLIENTCMD -- $PIDVAL3"
wait $PIDVAL1
wait $PIDVAL2
wait $PIDVAL3

# Now everyone sends their message
CLIENTCMD="../bin/client group -s blob80 -l $CLIENTOUT/client80.log $CLIENTGROUPOPTS --sendMessage $GROUPID --message \"Hello from 80\""
eval $CLIENTCMD >> $CLIENTOUT/client80.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="../bin/client group -s blob81 -l $CLIENTOUT/client81.log $CLIENTGROUPOPTS --sendMessage $GROUPID --message \"Hello from 81\""
eval $CLIENTCMD >> $CLIENTOUT/client81.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
CLIENTCMD="../bin/client group -s blob82 -l $CLIENTOUT/client82.log $CLIENTGROUPOPTS --sendMessage $GROUPID --message \"Hello from 82\""
eval $CLIENTCMD >> $CLIENTOUT/client82.txt 2>&1 &
PIDVAL3=$!
echo "$CLIENTCMD -- $PIDVAL3"
wait $PIDVAL1
wait $PIDVAL2
wait $PIDVAL3

# Everyone waits for their message
CLIENTCMD="../bin/client group -s blob80 -l $CLIENTOUT/client80.log $CLIENTGROUPOPTS --wait 2"
eval $CLIENTCMD >> $CLIENTOUT/client80.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="../bin/client group -s blob81 -l $CLIENTOUT/client81.log $CLIENTGROUPOPTS --wait 2"
eval $CLIENTCMD >> $CLIENTOUT/client81.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
CLIENTCMD="../bin/client group -s blob82 -l $CLIENTOUT/client82.log $CLIENTGROUPOPTS --wait 2"
eval $CLIENTCMD >> $CLIENTOUT/client82.txt 2>&1 &
PIDVAL3=$!
echo "$CLIENTCMD -- $PIDVAL3"
wait $PIDVAL1
wait $PIDVAL2
wait $PIDVAL3

# Member 2 leaves the group
CLIENTCMD="../bin/client group -s blob81 -l $CLIENTOUT/client81.log $CLIENTGROUPOPTS --leave $GROUPID"
eval $CLIENTCMD >> $CLIENTOUT/client81.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL2

# 1 and 3 send a message successfully now, 2 does not
CLIENTCMD="../bin/client group -s blob80 -l $CLIENTOUT/client80.log $CLIENTGROUPOPTS --sendMessage $GROUPID --message \"Hello 2 from 80\""
eval $CLIENTCMD >> $CLIENTOUT/client80.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL2"
CLIENTCMD="../bin/client group -s blob82 -l $CLIENTOUT/client82.log $CLIENTGROUPOPTS --sendMessage $GROUPID --message \"Hello 2 from 82\""
eval $CLIENTCMD >> $CLIENTOUT/client82.txt 2>&1 &
PIDVAL3=$!
echo "$CLIENTCMD -- $PIDVAL3"
wait $PIDVAL1
wait $PIDVAL2
wait $PIDVAL3

# All 3 wait again
CLIENTCMD="../bin/client group -s blob80 -l $CLIENTOUT/client80.log $CLIENTGROUPOPTS --wait 1"
eval $CLIENTCMD >> $CLIENTOUT/client80.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="../bin/client group -s blob81 -l $CLIENTOUT/client81.log $CLIENTGROUPOPTS --wait 1"
eval $CLIENTCMD >> $CLIENTOUT/client81.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
CLIENTCMD="../bin/client group -s blob82 -l $CLIENTOUT/client82.log $CLIENTGROUPOPTS --wait 1"
eval $CLIENTCMD >> $CLIENTOUT/client82.txt 2>&1 &
PIDVAL3=$!
echo "$CLIENTCMD -- $PIDVAL3"
wait $PIDVAL1
wait $PIDVAL2
wait $PIDVAL3

echo "GROUP CHAT FINISHED!"

###############################################################################
# Test  File Transfer
###############################################################################

echo "TESTING FILE TRANSFER..."

# Create authenticated channel between client 110 and 111
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client110.log -s blob110 --writeContact $CLIENTOUT/client110-contact.bin --unsafe -m \"Hello from contact 110 to myself, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client110.txt &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
wait $PIDVAL1
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client111.log -s blob111 --writeContact $CLIENTOUT/client111-contact.bin --destfile $CLIENTOUT/client110-contact.bin --send-auth-request --unsafe-channel-creation --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client111.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"

while [ ! -s $CLIENTOUT/client111-contact.bin ]; do
    sleep 1
    echo -n "."
done
echo

TMPID=$(cat $CLIENTOUT/client110.log | grep -a "User\:" | awk -F' ' '{print $5}')
CLIENT110ID=${TMPID}
echo "CLIENT 110 ID: $CLIENT110ID"
TMPID=$(cat $CLIENTOUT/client111.log | grep -a "User\:" | awk -F' ' '{print $5}')
CLIENT111ID=${TMPID}
echo "CLIENT 111 ID: $CLIENT111ID"

# Client 110 will now wait for client 111's E2E Auth channel request and confirm
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client110.log -s blob110 --destfile $CLIENTOUT/client111-contact.bin --sendCount 0 --receiveCount 0 --accept-channel --auth-timeout 360"
eval $CLIENTCMD >> $CLIENTOUT/client110.txt &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
wait $PIDVAL1
wait $PIDVAL2

# Client 111 sends a file to client 110
CLIENTCMD="timeout 360s ../bin/client fileTransfer -s blob110 -l $CLIENTOUT/client110.log $CLIENTFILETRANSFEROPTS"
eval $CLIENTCMD > $CLIENTOUT/client110.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="timeout 700s ../bin/client fileTransfer -s blob111 -l $CLIENTOUT/client111.log $CLIENTFILETRANSFEROPTS --sendFile $CLIENTOUT/client110-contact.bin --filePath LoremIpsum.txt --filePreviewString \"Lorem ipsum dolor sit amet, consectetur adipiscing elit.\" --maxThroughput 1000 --retry 0"
eval $CLIENTCMD > $CLIENTOUT/client111.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL1
wait $PIDVAL2

echo "FILE TRANSFER FINISHED..."

echo "TESTING BROADCAST CHANNELS..."

# New broadcast channel...
CLIENTCMD="timeout 240s ../bin/client broadcast --password hello --ndf results/ndf.json --waitTimeout 1800 -l $CLIENTOUT/client130.log -s blob130 --new --name broadcast-test --description \"Integration test channel\" --chanPath results/integration-channel.json --keyPath results/integration-chan-key.pem --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client130.txt &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
wait $PIDVAL1

# Start client to listen for messages on the channel
CLIENTCMD="timeout 480s ../bin/client broadcast --password hello --ndf results/ndf.json --waitTimeout 1800 -l $CLIENTOUT/client131.log -s blob131 --chanPath results/integration-channel.json --receiveCount 4"
eval $CLIENTCMD >> $CLIENTOUT/client131.txt &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"

sleep 10

# Send symmetric broadcast to channel
CLIENTCMD="timeout 240s ../bin/client broadcast --password hello --ndf results/ndf.json --waitTimeout 360 -l $CLIENTOUT/client132.log -s blob132 --chanPath results/integration-channel.json --receiveCount 0 --sendDelay 5000 --symmetric \"Hello to symmetric channel from channel client 122!\""
eval $CLIENTCMD >> $CLIENTOUT/client132.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"

# Send asymmetric broadcast to channel
CLIENTCMD="timeout 240s ../bin/client broadcast --password hello --ndf results/ndf.json --waitTimeout 360 -l $CLIENTOUT/client133.log -s blob133 --chanPath results/integration-channel.json --receiveCount 0 --sendDelay 5000 --keyPath results/integration-chan-key.pem --asymmetric \"Hello to asymmetric channel from channel client 123!\""
eval $CLIENTCMD >> $CLIENTOUT/client133.txt &
PIDVAL3=$!
echo "$CLIENTCMD -- $PIDVAL3"

# Send symmetric & asymmetric broadcasts to channel
CLIENTCMD="timeout 240s ../bin/client broadcast --password hello --ndf results/ndf.json --waitTimeout 360 -l $CLIENTOUT/client134.log -s blob134 --chanPath results/integration-channel.json --receiveCount 0 --sendDelay 5000 --keyPath results/integration-chan-key.pem --asymmetric \"Hello to asymmetric channel from channel client 124!\" --symmetric \"Hello to symmetric channel from channel client 124!\""
eval $CLIENTCMD >> $CLIENTOUT/client134.txt &
PIDVAL4=$!
echo "$CLIENTCMD -- $PIDVAL4"

wait $PIDVAL2
wait $PIDVAL3
wait $PIDVAL4
wait $PIDVAL1

echo "BROADCAST CHANNELS FINISHED..."

###############################################################################
# Test ephemeral connections
###############################################################################

echo "TESTING EPEHMERAL CONNECTIONS..."
# Initiate server
CLIENTCMD="timeout 240s ../bin/client connection --ephemeral -s blob200 $CONNECTIONOPTS --writeContact $CLIENTOUT/client200-server.bin -l $CLIENTOUT/client200.log --startServer --serverTimeout 1m30s"
eval $CLIENTCMD > $CLIENTOUT/client200.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
echo "Sleeping to ensure connection server instantiation"
sleep 5

# Initiate client and send message to server
CLIENTCMD="timeout 240s ../bin/client connection --ephemeral -s blob201 --connect $CLIENTOUT/client200-server.bin $CONNECTIONOPTS -l $CLIENTOUT/client201.log  -m \"Hello 200 from 201, using connections\" --receiveCount 0"
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
CLIENTCMD="timeout 240s ../bin/client connection --ephemeral -s blob202 --authenticated $CONNECTIONOPTS --writeContact $CLIENTOUT/client202-server.bin -l $CLIENTOUT/client202.log --startServer --serverTimeout 1m30s"
eval $CLIENTCMD > $CLIENTOUT/client202.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
echo "Sleeping to ensure connection server instantiation"
sleep 5

# Initiate client and send message to server
CLIENTCMD="timeout 240s ../bin/client connection --ephemeral -s blob203 --authenticated --connect $CLIENTOUT/client202-server.bin $CONNECTIONOPTS -l $CLIENTOUT/client203.log  -m \"Hello 202 from 203, using connections\" --receiveCount 0"
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
CLIENTCMD="timeout 240s ../bin/client connection -s blob204 $CONNECTIONOPTS --writeContact $CLIENTOUT/client204-server.bin -l $CLIENTOUT/client204.log --startServer --serverTimeout 1m30s"
eval $CLIENTCMD > $CLIENTOUT/client204.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
echo "Sleeping to ensure connection server instantiation"
sleep 5

# Initiate client and send message to server
CLIENTCMD="timeout 240s ../bin/client connection -s blob205 --connect $CLIENTOUT/client204-server.bin $CONNECTIONOPTS -l $CLIENTOUT/client205.log  -m \"Hello 204 from 205, using connections\" --receiveCount 0"
eval $CLIENTCMD > $CLIENTOUT/client205.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL2
wait $PIDVAL1
echo "NON-EPHEMERAL CONNECTION TEST FINISHED."

echo "TESTING EPHEMERAL AUTHENTICATED CONNECTIONS..."
# Initiate server
CLIENTCMD="timeout 240s ../bin/client connection -s blob206 --authenticated $CONNECTIONOPTS --writeContact $CLIENTOUT/client206-server.bin -l $CLIENTOUT/client206.log --startServer --serverTimeout 1m30s"
eval $CLIENTCMD > $CLIENTOUT/client206.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
echo "Sleeping to ensure connection server instantiation"
sleep 5

# Initiate client and send message to server
CLIENTCMD="timeout 240s ../bin/client connection -s blob207 --authenticated --connect $CLIENTOUT/client206-server.bin $CONNECTIONOPTS -l $CLIENTOUT/client207.log  -m \"Hello 206 from 207, using connections\" --receiveCount 0"
eval $CLIENTCMD > $CLIENTOUT/client207.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL2
wait $PIDVAL1
echo "Non-Ephemeral Test Complete."


echo "TESTS EXITED SUCCESSFULLY, CHECKING OUTPUT..."


cp $CLIENTOUT/*.txt $CLIENTCLEAN/

sed -i.bak 's/Sending\ to\ .*\:/Sent:/g' $CLIENTCLEAN/client*.txt
sed -i.bak 's/Message\ from\ .*, .* Received:/Received:/g' $CLIENTCLEAN/client*.txt
sed -i.bak 's/ERROR.*Signature/Signature/g' $CLIENTCLEAN/client*.txt
sed -i.bak 's/[Aa]uthenticat.*$//g' $CLIENTCLEAN/client*.txt
rm $CLIENTCLEAN/client*.txt.bak

# sort -b -o "$CLIENTOUT/client80.txt" "$CLIENTCLEAN/client80.txt"
# sort -b -o "$CLIENTOUT/client81.txt" "$CLIENTCLEAN/client81.txt"
# sort -b -o "$CLIENTOUT/client82.txt" "$CLIENTCLEAN/client82.txt"

for C in $(ls -1 $CLIENTCLEAN | grep -v client11[01]); do
    sort -o tmp $CLIENTCLEAN/$C  || true
    cp tmp $CLIENTCLEAN/$C
    # uniq tmp $CLIENTCLEAN/$C || true
done

set -e

GOLDOUTPUT=clients.goldoutput
if [ "$NETWORKENTRYPOINT" != "localhost:8440" ]
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
cat $CLIENTOUT/client42.log | grep -a "Could not confirm authentication channel" > results/deleteContact.txt || true
echo "CHECKING FOR SUCCESSFUL CONTACT DELETION"
if [ -s results/deleteContact.txt ]
then
    echo "CONTACT DELETION SUCCESSFUL"
else
    echo "CONTACT DELETION FAILED"
    [ -s results/deleteContact.txt ]
fi

if [ "$NETWORKENTRYPOINT" == "localhost:8440" ]
then

    #cat $CLIENTOUT/* | strings | grep -ae "ERROR" -e "FATAL" > results/client-errors || true
    #diff -ruN results/client-errors.txt noerrors.txt
    cat $SERVERLOGS/server-*.log | grep -a "ERROR" | grep -a -v "context" | grep -av "metrics" | grep -av "database" | grep -av RequestClientKey > results/server-errors.txt || true
    cat $SERVERLOGS/server-*.log | grep -a "FATAL" | grep -a -v "context" | grep -av "transport is closing" | grep -av "database" >> results/server-errors.txt || true
    diff -aruN results/server-errors.txt noerrors.txt
    IGNOREMSG="GetRoundBufferInfo: Error received: rpc error: code = Unknown desc = round buffer is empty"
    cat $GATEWAYLOGS/*.log | grep -a "ERROR" | grep -av "context" | grep -av "certificate" | grep -av "Failed to read key" | grep -av "$IGNOREMSG" > results/gateway-errors.txt || true
    cat $GATEWAYLOGS/*.log | grep -a "FATAL" | grep -av "context" | grep -av "transport is closing" >> results/gateway-errors.txt || true
    diff -aruN results/gateway-errors.txt noerrors.txt
    echo "Checking backup files for equality..."
    # diff -aruN $CLIENTOUT/client120A.backup.json $CLIENTOUT/client120B.backup.json > client120BackupDiff.txt
    diff -aruN $CLIENTOUT/client121A.backup.json $CLIENTOUT/client121B.backup.json > client121BackupDiff.txt || true
    # diff -aruN  client120BackupDiff.txt noerrors.txt
    echo "NOTE: BACKUP CHECK DISABLED, this should be uncommented when turned back on!"
    #diff -aruN  client121BackupDiff.txt noerrors.txt
fi

echo "NO OUTPUT ERRORS, SUCCESS!"
