#!/bin/bash

# NOTE: This is verbose on purpose.

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

CLIENTOPTS="--password hello --ndf results/ndf.json --verify-sends --sendDelay 100 --waitTimeout 360 --unsafe-channel-creation -v $DEBUGLEVEL"
CLIENTUDOPTS="--password hello --ndf results/ndf.json -v $DEBUGLEVEL"
CLIENTSINGLEOPTS="--password hello --waitTimeout 360 --ndf results/ndf.json -v $DEBUGLEVEL"
CLIENTGROUPOPTS="--password hello --waitTimeout 360 --ndf results/ndf.json -v $DEBUGLEVEL"
CLIENTFILETRANSFEROPTS="--password hello --waitTimeout 360 --ndf results/ndf.json -v $DEBUGLEVEL"
CLIENTREKEYOPTS="--password hello --ndf results/ndf.json --verify-sends --waitTimeout 420 --unsafe-channel-creation -v $DEBUGLEVEL"

mkdir -p $SERVERLOGS
mkdir -p $GATEWAYLOGS
mkdir -p $CLIENTOUT
mkdir -p $CLIENTCLEAN

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
    echo "STARTING SERVERS..."

    # Copy udbContact into place when running locally.
    cp udbContact.bin results/udbContact.bin

    PERMCMD="../bin/permissioning --logLevel $DEBUGLEVEL -c permissioning.yaml "
    $PERMCMD > results/permissioning-console.txt 2>&1 &
    PIDVAL=$!
    echo "$PERMCMD -- $PIDVAL"


    # Run Client Registrar
    CLIENT_REG_CMD="../bin/client-registrar \
    -l 2 -c client-registrar.yaml"
    $CLIENT_REG_CMD > results/client-registrat-console.txt 2>&1 &
    PIDVAL=$!
    echo "$CLIENT_REG_CMD -- $PIDVAL"

    for SERVERID in $(seq 5 -1 1)
    do
        IDX=$(($SERVERID - 1))
        SERVERCMD="../bin/server --logLevel $DEBUGLEVEL --config server-$SERVERID.yaml"
        if [ $SERVERID -eq 5 ] && [ -n "$NSYSENABLED" ]
        then
            SERVERCMD="nsys profile --session-new=gputest --trace=cuda -o server-$SERVERID $SERVERCMD"
        fi
        $SERVERCMD > $SERVERLOGS/server-$SERVERID-console.txt 2>&1 &
        PIDVAL=$!
        echo "$SERVERCMD -- $PIDVAL"
    done

    # Start gateways
    for GWID in $(seq 5 -1 1)
    do
        IDX=$(($GWID - 1))
        GATEWAYCMD="../bin/gateway --logLevel $DEBUGLEVEL --config gateway-$GWID.yaml"
        $GATEWAYCMD > $GATEWAYLOGS/gateway-$GWID-console.txt 2>&1 &
        PIDVAL=$!
        echo "$GATEWAYCMD -- $PIDVAL"
    done

    jobs -p > results/serverpids

    finish() {
        echo "STOPPING SERVERS AND GATEWAYS..."
        if [ -n "$NSYSENABLED" ]
        then
            nsys stop --session=gputest
        fi
        # NOTE: jobs -p doesn't work in a signal handler
        for job in $(cat results/serverpids)
        do
            echo "KILLING $job"
            kill $job || true
        done

        sleep 5

        for job in $(cat results/serverpids)
        do
            echo "KILL -9 $job"
            kill -9 $job || true
        done
        #tail $SERVERLOGS/*
        #tail $CLIENTCLEAN/*
        #diff -aruN clients.goldoutput $CLIENTCLEAN
    }

    trap finish EXIT
    trap finish INT

    # Sleeps can die in a fire on the sun, we wait for the servers to start running
    # rounds
    rm rid.txt || true
    touch rid.txt
    cnt=0
    echo -n "Waiting for a round to run"
    while [ ! -s rid.txt ] && [ $cnt -lt 120 ]; do
        sleep 1
        grep -a "RID 1 ReceiveFinishRealtime END" results/servers/server-* > rid.txt || true
        cnt=$(($cnt + 1))
        echo -n "."
    done

    # Start a user discovery bot server
    echo "STARTING UDB..."
    UDBCMD="../bin/udb --logLevel $DEBUGLEVEL --protoUserPath	udbProto.json --config udb.yaml -l 1"
    $UDBCMD >> $UDBOUT 2>&1 &
    PIDVAL=$!
    echo $PIDVAL >> results/serverpids
    echo "$UDBCMD -- $PIDVAL"
    rm rid.txt || true
    while [ ! -s rid.txt ] && [ $cnt -lt 30 ]; do
        sleep 1
        grep -a "Sending Poll message" results/udb-console.txt > rid.txt || true
        cnt=$(($cnt + 1))
        echo -n "."
    done

    echo "localhost:8440" > results/startgwserver.txt

    echo "DONE LETS DO STUFF"

else
    echo "Connecting to network defined at $NETWORKENTRYPOINT"
    echo $NETWORKENTRYPOINT > results/startgwserver.txt
fi

echo "DOWNLOADING TLS Cert..."
CMD="openssl s_client -showcerts -connect $(cat results/startgwserver.txt)"
echo $CMD
eval $CMD < /dev/null 2>&1 > "results/startgwcert.bin"
CMD="cat results/startgwcert.bin | openssl x509 -outform PEM"
echo $CMD
eval $CMD > "results/startgwcert.pem"
head "results/startgwcert.pem"

echo "DOWNLOADING NDF..."
CLIENTCMD="../bin/client getndf --gwhost $(cat results/startgwserver.txt) --cert results/startgwcert.pem"
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
    eval $CLIENTCMD >> $CLIENTOUT/client18_rekey.txt 2>&1 || true &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client9_rekey.log --sendCount 20 --receiveCount 20 --destid 18 -s blob9/blob9 -m \"Hello, 18, with E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client9_rekey.txt 2>&1 || true &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    wait $PIDVAL || true

    echo "FORCING HISTORICAL ROUNDS... (NON-E2E, PRECAN)"
    CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS --forceHistoricalRounds --unsafe -l $CLIENTOUT/client33.log -s blob33 --sendid 1 --destid 2 --sendCount 5 --receiveCount 5 -m \"Hello from 1, without E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client33.txt || true &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS --forceHistoricalRounds --unsafe -l $CLIENTOUT/client34.log -s blob34 --sendid 2 --destid 1 --sendCount 5 --receiveCount 5 -m \"Hello from 2, without E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client34.txt || true &
    PIDVAL2=$!
    echo "$CLIENTCMD -- $PIDVAL"
    wait $PIDVAL
    wait $PIDVAL2

    echo "FORCING MESSAGE PICKUP RETRY... (NON-E2E, PRECAN)"
    # Higher timeouts for this test to allow message pickup retry to function
    CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS --forceMessagePickupRetry --unsafe -l $CLIENTOUT/client20.log -s blob20 --sendid 20 --destid 21 --sendCount 5 --receiveCount 5 -m \"Hello from 20, without E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client20.txt || true &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS --forceMessagePickupRetry --unsafe -l $CLIENTOUT/client21.log -s blob21 --sendid 21 --destid 20 --sendCount 5 --receiveCount 5 -m \"Hello from 21, without E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client21.txt || true &
    PIDVAL2=$!
    echo "$CLIENTCMD -- $PIDVAL"
    wait $PIDVAL
    wait $PIDVAL2


fi

# Non-precanned E2E user messaging
echo "SENDING E2E MESSAGES TO NEW USERS..."
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blob42 --writeContact $CLIENTOUT/rick42-contact.bin --unsafe -m \"Hello from Rick42 to myself, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client42.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -s blob43 --writeContact $CLIENTOUT/ben43-contact.bin --destfile $CLIENTOUT/rick42-contact.bin --send-auth-request --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client43.txt || true &
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
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blob42 --destfile $CLIENTOUT/ben43-contact.bin --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client42.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

# Test destid syntax too, note wait for 11 messages to catch the message from above ^^^
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blob42  --destid b64:$BENID --sendCount 5 --receiveCount 5 -m \"Hello from Rick42, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client42.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -s blob43  --destid b64:$RICKID --sendCount 5 --receiveCount 5 -m \"Hello from Ben43, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client43.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blob42  --destid b64:$BENID --sendCount 5 --receiveCount 5 -m \"Hello from Rick42, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client42.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -s blob43  --destid b64:$RICKID --sendCount 5 --receiveCount 5 -m \"Hello from Ben43, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client43.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

echo "TESTING RENEGOTIATION..."
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -s blob43 --destfile $CLIENTOUT/rick42-contact.bin --send-auth-request --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client43.txt || true &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
# Client 42 will now wait, again, for client 43's E2E Auth channel request and confirm
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blob42 --destfile $CLIENTOUT/ben43-contact.bin --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client42.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL1
wait $PIDVAL2
#Send a few messages
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blob42  --destid b64:$BENID --sendCount 5 --receiveCount 5 -m \"Hello from Rick42, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client42.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -s blob43  --destid b64:$RICKID --sendCount 5 --receiveCount 5 -m \"Hello from Ben43, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client43.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL
wait $PIDVAL2

echo "SWITCHING RENEGOTIATION TEST..."
# Switch places, 42 renegotiates with 43
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blob42 --destfile $CLIENTOUT/ben43-contact.bin --send-auth-request --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client42.txt || true &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
# Client 43 will now wait, for client 42's renegotiated E2E Auth channel request and confirm
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -s blob43 --destfile $CLIENTOUT/rick42-contact.bin --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client43.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL1
wait $PIDVAL2
#Send a few more messages
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blob42  --destid b64:$BENID --sendCount 5 --receiveCount 5 -m \"Hello from Rick42, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client42.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -s blob43  --destid b64:$RICKID --sendCount 5 --receiveCount 5 -m \"Hello from Ben43, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client43.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL
wait $PIDVAL2
echo "END RENEGOTIATION"

echo "DELETING CONTACT FROM CLIENT..."
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blob42 --delete-channel --destfile $CLIENTOUT/ben43-contact.bin --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client42.txt || true &
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
eval $CLIENTCMD >> $CLIENTOUT/client44.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client45.log -s blob45 --writeContact $CLIENTOUT/matt45-contact.bin --destfile $CLIENTOUT/matt45-contact.bin --send-auth-request --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client45.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"

TMPID=$(cat $CLIENTOUT/client44.log | grep -a "User\:" | awk -F' ' '{print $5}')
DAVIDID=${TMPID}
echo "BEN ID: $DAVIDID"

CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client45.log -s blob45 --delete-sent-requests --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client45.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"

CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blob42  --destid b64:$DAVIDID --sendCount 5 --receiveCount 5 -m \"Hello from David, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client42.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
echo "NOTE: The command above causes an EXPECTED failure to confirm authentication channel!"
wait $PIDVAL2


echo "CREATING USERS for SIMULTANEOUSAUTH TEST..."
JONOID=$(../bin/client init -s blob85 -l $CLIENTOUT/client85.log --password hello --ndf results/ndf.json --writeContact $CLIENTOUT/jono85-contact.bin -v $DEBUGLEVEL)
SYDNEYID=$(../bin/client init -s blob86 -l $CLIENTOUT/client86.log --password hello --ndf results/ndf.json --writeContact $CLIENTOUT/sydney86-contact.bin -v $DEBUGLEVEL)
echo "JONO ID: $JONOID"
echo "SYDNEY ID: $SYDNEYID"

# Attempt to send an auth request at the same time. It's not guaranteed that
# one side won't send and the other won't receive before sending their request
# but this method has proven to be reasonably reliable.
echo "STARTING SIMULTANEOUSAUTH TEST..."
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client85.log -s blob85 --destfile $CLIENTOUT/sydney86-contact.bin --send-auth-request --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client85.txt || true &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client86.log -s blob86 --destfile $CLIENTOUT/jono85-contact.bin --send-auth-request --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client86.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL1
wait $PIDVAL2

# Send a couple messages
echo "TESTING SIMULTANEOUSAUTH MESSAGE SEND..."
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client85.log -s blob85 --destfile $CLIENTOUT/sydney86-contact.bin --sendCount 5 --receiveCount 5 -m \"Hello Sydney from Jono, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client85.txt || true &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client86.log -s blob86 --destfile $CLIENTOUT/jono85-contact.bin --sendCount 5 --receiveCount 5 -m \"Hello Jono from Sydney, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client86.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL1
wait $PIDVAL2


echo "CREATING USERS for REKEY TEST..."
JAKEID=$(../bin/client init -s blob100 -l $CLIENTOUT/client100.log --password hello --ndf results/ndf.json --writeContact $CLIENTOUT/Jake100-contact.bin -v $DEBUGLEVEL)
NIAMHID=$(../bin/client init -s blob101 -l $CLIENTOUT/client101.log --password hello --ndf results/ndf.json --writeContact $CLIENTOUT/Niamh101-contact.bin -v $DEBUGLEVEL)
echo "JAKE ID: $JAKEID"
echo "NIAMH ID: $NIAMHID"


REKEYOPTS="--e2eMaxKeys 15 --e2eMinKeys 10 --e2eNumReKeys 5 --e2eRekeyThreshold 0.75"
# Client 101 will now send auth request
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS $REKEYOPTS -l $CLIENTOUT/client101.log -s blob101 --writeContact $CLIENTOUT/Niamh101-contact.bin --destfile $CLIENTOUT/Jake100-contact.bin --send-auth-request --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client101.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
# Client 100 will now wait for client 101's E2E Auth channel request and confirm
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS $REKEYOPTS -l $CLIENTOUT/client100.log -s blob100 --destid b64:$NIAMHID --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client100.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

echo "RUNNING REKEY TEST..."
# Test destid syntax too, note wait for 11 messages to catch the message from above ^^^
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS $REKEYOPTS -l $CLIENTOUT/client100.log -s blob100 --destid b64:$NIAMHID --sendCount 20 --receiveCount 20 -m \"Hello from Jake100, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client100.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS $REKEYOPTS -l $CLIENTOUT/client101.log -s blob101 --destid b64:$JAKEID --sendCount 20 --receiveCount 20 -m \"Hello from Niamh101, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client101.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

# Now we are just going to exhaust all the keys we have and see if we
# use the unconfirmed channels
CLIENTCMD="timeout 420s ../bin/client $CLIENTREKEYOPTS $REKEYOPTS -l $CLIENTOUT/client100.log -s blob100 --destid b64:$NIAMHID --sendCount 20 --receiveCount 0 -m \"Hello from Jake100, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client100.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
# And receive those messages sent to us
CLIENTCMD="timeout 420s ../bin/client $CLIENTREKEYOPTS $REKEYOPTS -l $CLIENTOUT/client101.log -s blob101 --destid b64:$JAKEID --sendCount 0 --receiveCount 20"
eval $CLIENTCMD >> $CLIENTOUT/client101.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL2


echo "FORCING HISTORICAL ROUNDS..."
FH1ID=$(../bin/client init -s blob35 -l $CLIENTOUT/client35.log --password hello --ndf results/ndf.json --writeContact $CLIENTOUT/FH1-contact.bin -v $DEBUGLEVEL)
FH2ID=$(../bin/client init -s blob36 -l $CLIENTOUT/client36.log --password hello --ndf results/ndf.json --writeContact $CLIENTOUT/FH2-contact.bin -v $DEBUGLEVEL)
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS --forceHistoricalRounds --unsafe -l $CLIENTOUT/client35.log -s blob35 --destid b64:$FH2ID --sendCount 5 --receiveCount 5 -m \"Hello from 35, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client35.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS --forceHistoricalRounds --unsafe -l $CLIENTOUT/client36.log -s blob36 --destid b64:$FH1ID --sendCount 5 --receiveCount 5 -m \"Hello from 36, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client36.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

echo "FORCING MESSAGE PICKUP RETRY... "
FM1ID=$(../bin/client init -s blob22 -l $CLIENTOUT/client22.log --password hello --ndf results/ndf.json --writeContact $CLIENTOUT/FM1-contact.bin -v $DEBUGLEVEL)
FM2ID=$(../bin/client init -s blob23 -l $CLIENTOUT/client23.log --password hello --ndf results/ndf.json --writeContact $CLIENTOUT/FM2-contact.bin -v $DEBUGLEVEL)
# Higher timeouts for this test to allow message pickup retry to function
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS --forceMessagePickupRetry -l $CLIENTOUT/client22.log -s blob22 --destid b64:$FM2ID --sendCount 5 --receiveCount 5 -m \"Hello from 22, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client22.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS --forceMessagePickupRetry -l $CLIENTOUT/client23.log -s blob23  --destid b64:$FM1ID --sendCount 5 --receiveCount 5 -m \"Hello from 23, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client23.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

echo "CREATING USERS FOR BACKUP..."
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client120.log -s blob120A --writeContact $CLIENTOUT/client120-contact.bin --unsafe -m \"Hello from Client120 to myself, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client120.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client121.log -s blob121A --writeContact $CLIENTOUT/client121-contact.bin --destfile $CLIENTOUT/client120-contact.bin --send-auth-request --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client121.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"

while [ ! -s $CLIENTOUT/client121-contact.bin ]; do
    sleep 1
    echo -n "."
done

wait $PIDVAL2

TMPID=$(cat $CLIENTOUT/client120.log | grep -a "User\:" | awk -F' ' '{print $5}')
CLIENT120ID=${TMPID}
echo "CLIENT 120 ID: $CLIENT120ID"
TMPID=$(cat $CLIENTOUT/client121.log | grep -a "User\:" | awk -F' ' '{print $5}')
CLIENT121ID=${TMPID}
echo "BEN ID: $CLIENT121ID"

# Client 120 will now wait for client 121's E2E Auth channel request and confirm
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client120.log -s blob120A --destfile $CLIENTOUT/client121-contact.bin --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client120.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

# Send messages
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client120.log -s blob120A  --destid b64:$CLIENT121ID --sendCount 5 --receiveCount 5 -m \"Hello from Client120, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client120.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client121.log -s blob121A  --destid b64:$CLIENT120ID --sendCount 5 --receiveCount 5 -m \"Hello from Client121, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client121.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2


# Backup 120 and restore
CLIENTCMD="timeout 20s ../bin/client -l $CLIENTOUT/client120.log -s blob120A --password hello --ndf results/ndf.json -v $DEBUGLEVEL --backupOut $CLIENTOUT/client120A.backup  --backupPass hello --backupJsonOut $CLIENTOUT/client120A.backup.json"
eval $CLIENTCMD >> $CLIENTOUT/client120.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

CLIENTCMD="timeout 20s ../bin/client  -l $CLIENTOUT/client120.log -s blob120B --password hello --ndf results/ndf.json -v $DEBUGLEVEL --backupIn $CLIENTOUT/client120A.backup --backupPass hello --backupJsonOut $CLIENTOUT/client120B.backup.json --backupIdList $CLIENTOUT/client120Partners.json"
eval $CLIENTCMD >> $CLIENTOUT/client120.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

CLIENTCMD="timeout 240s ../bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client120.log -s blob120B --batchadd $CLIENTOUT/client120Partners.json"
eval $CLIENTCMD >> $CLIENTOUT/client120.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL


# Send messages
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client120.log -s blob120B  --destid b64:$CLIENT121ID --sendCount 5 --receiveCount 5 -m \"Hello from Client120, with E2E Encryption after 120 restoring backup\""
eval $CLIENTCMD >> $CLIENTOUT/client120.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client121.log -s blob121A  --destid b64:$CLIENT120ID --sendCount 5 --receiveCount 5 -m \"Hello from Client121, with E2E Encryption after 120 restoring backup\""
eval $CLIENTCMD >> $CLIENTOUT/client121.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2


# Backup 121 and restore
CLIENTCMD="timeout 20s ../bin/client -l $CLIENTOUT/client121.log -s blob121A --password hello --ndf results/ndf.json -v $DEBUGLEVEL --backupOut $CLIENTOUT/client121A.backup  --backupPass hello --backupJsonOut $CLIENTOUT/client121A.backup.json"
eval $CLIENTCMD >> $CLIENTOUT/client121.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

CLIENTCMD="timeout 20s ../bin/client  -l $CLIENTOUT/client121.log -s blob121B --password hello --ndf results/ndf.json -v $DEBUGLEVEL --backupIn $CLIENTOUT/client121A.backup --backupPass hello --backupJsonOut $CLIENTOUT/client121B.backup.json --backupIdList $CLIENTOUT/client121Partners.json"
eval $CLIENTCMD >> $CLIENTOUT/client121.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

CLIENTCMD="timeout 240s ../bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client121.log -s blob121B --batchadd $CLIENTOUT/client121Partners.json"
eval $CLIENTCMD >> $CLIENTOUT/client121.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL


# Send messages
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client120.log -s blob120B  --destid b64:$CLIENT121ID --sendCount 5 --receiveCount 5 -m \"Hello from Client120, with E2E Encryption after 121 restoring backup\""
eval $CLIENTCMD >> $CLIENTOUT/client120.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client121.log -s blob121B  --destid b64:$CLIENT120ID --sendCount 5 --receiveCount 5 -m \"Hello from Client121, with E2E Encryption after 121 restoring backup\""
eval $CLIENTCMD >> $CLIENTOUT/client121.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2


# Proto user test: client25 and client26 generate a proto user JSON file and close.
# Both clients are restarted and load from their respective proto user files and attempt to send.

# Generate contact and proto user file for client25
echo "TESTING PROTO USER FILE..."

CLIENTCMD="timeout 20s ../bin/client  -l $CLIENTOUT/client25.log -s blob11420 --password hello --ndf results/ndf.json --writeContact $CLIENTOUT/josh25-contact.bin --protoUserOut $CLIENTOUT/client25Proto.json "
eval $CLIENTCMD >> $CLIENTOUT/client25.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

# Generate contact and proto user file for client 26
CLIENTCMD="timeout 20s ../bin/client  -l $CLIENTOUT/client26.log -s blob11421 --password hello --ndf results/ndf.json --writeContact $CLIENTOUT/jonah26-contact.bin --protoUserOut $CLIENTOUT/client26Proto.json"
eval $CLIENTCMD >> $CLIENTOUT/client26.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

# Clients will now load from the protoUser file and write to session
CLIENTCMD="timeout 60s ../bin/client  $CLIENTOPTS -l $CLIENTOUT/client25.log -s blob25  --protoUserPath $CLIENTOUT/client25Proto.json"
eval $CLIENTCMD >> $CLIENTOUT/client25.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 60s ../bin/client  $CLIENTOPTS -l $CLIENTOUT/client26.log -s blob26  --protoUserPath $CLIENTOUT/client26Proto.json"
eval $CLIENTCMD >> $CLIENTOUT/client26.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL
wait $PIDVAL2

# Continue with E2E testing with session files loaded from proto
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client25.log -s blob25 --writeContact $CLIENTOUT/josh25-contact.bin --unsafe -m \"Hello from Josh25 to myself, without E2E Encryption\" "
eval $CLIENTCMD >> $CLIENTOUT/client25.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client26.log -s blob26 --writeContact $CLIENTOUT/jonah26-contact.bin --destfile $CLIENTOUT/josh25-contact.bin --send-auth-request --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client26.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"

while [ ! -s $CLIENTOUT/jonah26-contact.bin ]; do
    sleep 1
    echo -n "."
done

# Print IDs to console
TMPID=$(cat $CLIENTOUT/client25.log | grep -a "User\:" | awk -F' ' '{print $5}' | head -1)
JOSHID=${TMPID}
echo "JOSH ID: $JOSHID"
TMPID=$(cat $CLIENTOUT/client26.log | grep -a "User\:" | awk -F' ' '{print $5}' | head -1)
JONAHID=${TMPID}
echo "JONAH ID: $JONAHID"

## Client 25 will now wait for client 26's E2E Auth channel request and confirm
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client25.log -s blob25 --destfile $CLIENTOUT/jonah26-contact.bin --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client25.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2
#

# Send E2E messages with written sessions
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client25.log -s blob25 --destid b64:$JONAHID --sendCount 5 --receiveCount 5 -m \"Hello from Josh25, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client25.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client26.log -s blob26  --destid b64:$JOSHID --sendCount 5 --receiveCount 5 -m \"Hello from Jonah26, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client26.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client25.log -s blob25 --destid b64:$JONAHID --sendCount 5 --receiveCount 5 -m \"Hello from Josh25, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client25.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client26.log -s blob26 --destid b64:$JOSHID --sendCount 5 --receiveCount 5 -m \"Hello from Jonah26, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client26.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2


# Single-use test: client53 sends message to client52; client52 responds with
# the same message in the set number of message parts
echo "TESTING SINGLE-USE"

# Generate contact file for client52
CLIENTCMD="../bin/client init -s blob52 -l $CLIENTOUT/client52.log --password hello --ndf results/ndf.json --writeContact $CLIENTOUT/jono52-contact.bin"
eval $CLIENTCMD >> /dev/null 2>&1 || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

# Start client53, which sends a message and then waits for a response
CLIENTCMD="timeout 240s ../bin/client single $CLIENTSINGLEOPTS -l $CLIENTOUT/client53.log -s blob53 --maxMessages 8 --message \"Test single-use message\" --send -c $CLIENTOUT/jono52-contact.bin --timeout 90s"
eval $CLIENTCMD >> $CLIENTOUT/client53.txt 2>&1 || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"

# Start client52, which waits for a message and then responds
CLIENTCMD="timeout 240s ../bin/client single $CLIENTSINGLEOPTS -l $CLIENTOUT/client52.log -s blob52 --reply --timeout 90s"
eval $CLIENTCMD >> $CLIENTOUT/client52.txt 2>&1 || true &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
wait $PIDVAL1
wait $PIDVAL2


if [ "$NETWORKENTRYPOINT" == "localhost:8440" ]
then
    # UD Test
    echo "TESTING USER DISCOVERY..."
    CLIENTCMD="timeout 240s ../bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client13.log -s blob13 --register josh13 --addemail josh13@elixxir.io --addphone 6178675309US"
    eval $CLIENTCMD >> $CLIENTOUT/client13.txt || true &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    wait $PIDVAL
    CLIENTCMD="timeout 240s ../bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client31.log -s blob31 --register josh31 --addemail josh31@elixxir.io --addphone 6178675310US"
    eval $CLIENTCMD >> $CLIENTOUT/client31.txt || true &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    wait $PIDVAL

    CLIENTCMD="timeout 240s ../bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client13.log -s blob13 --searchusername josh31 --searchemail josh31@elixxir.io --searchphone 6178675310US"
    eval $CLIENTCMD > $CLIENTOUT/josh31.bin|| true &
    PIDVAL1=$!
    echo "$CLIENTCMD -- $PIDVAL1"
    CLIENTCMD="timeout 240s ../bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client31.log -s blob31 --searchusername josh13 --searchemail josh13@elixxir.io --searchphone 6178675309US"
    eval $CLIENTCMD > $CLIENTOUT/josh13.bin || true &
    PIDVAL2=$!
    echo "$CLIENTCMD -- $PIDVAL2"
    wait $PIDVAL1
    wait $PIDVAL2

    # Send auth chan request
    CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client13.log -s blob13 --destfile $CLIENTOUT/josh31.bin --send-auth-request --sendCount 0 --receiveCount 0"
    eval $CLIENTCMD >> $CLIENTOUT/client13.txt || true &
    PIDVAL2=$!
    echo "$CLIENTCMD -- $PIDVAL2"

    # Approve request and confirm
    CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client31.log -s blob31 --destfile $CLIENTOUT/josh13.bin --sendCount 0 --receiveCount 0"
    eval $CLIENTCMD >> $CLIENTOUT/client31.txt || true &
    PIDVAL1=$!
    echo "$CLIENTCMD -- $PIDVAL2"
    wait $PIDVAL1
    wait $PIDVAL2

    # now test
    CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client31.log -s blob31 --destfile $CLIENTOUT/josh13.bin --sendCount 5 --receiveCount 5 -m \"Hello from Josh31, with E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client31.txt || true &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client13.log -s blob13 --destfile $CLIENTOUT/josh31.bin --sendCount 5 --receiveCount 5 -m \"Hello from Josh13, with E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client13.txt || true &
    PIDVAL2=$!
    echo "$CLIENTCMD -- $PIDVAL"
    wait $PIDVAL
    wait $PIDVAL2

    # Test Remove User
    CLIENTCMD="timeout 240s ../bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client13.log -s blob13 --remove josh13"
    eval $CLIENTCMD >> $CLIENTOUT/client13.txt || true &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    wait $PIDVAL
    CLIENTCMD="timeout 240s ../bin/client ud $CLIENTUDOPTS -l $CLIENTOUT/client13-2.log -s blob13-2 --register josh13"
    eval $CLIENTCMD >> $CLIENTOUT/client13-2.txt || true &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    wait $PIDVAL
fi



echo "TESTING GROUP CHAT..."
# Create authenticated channel between client 80 and 81
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client80.log -s blob80 --writeContact $CLIENTOUT/client80-contact.bin --unsafe -m \"Hello from contact 80 to myself, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client80.txt || true &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
wait $PIDVAL1
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client81.log -s blob81 --writeContact $CLIENTOUT/client81-contact.bin --destfile $CLIENTOUT/client80-contact.bin --send-auth-request --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client81.txt || true &
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
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client80.log -s blob80 --destfile $CLIENTOUT/client81-contact.bin --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client80.txt || true &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
wait $PIDVAL1
wait $PIDVAL2


# Create authenticated channel between client 80 and 82
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client82.log -s blob82 --writeContact $CLIENTOUT/client82-contact.bin --destfile $CLIENTOUT/client80-contact.bin --send-auth-request --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client82.txt || true &
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
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client80.log -s blob80 --destfile $CLIENTOUT/client82-contact.bin --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client80.txt || true &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
wait $PIDVAL1
wait $PIDVAL3

# User 1 Creates Group
echo "Group User IDs: $CLIENT80ID $CLIENT81ID $CLIENT82ID"
echo "b64:$CLIENT81ID" > $CLIENTOUT/groupParticipants
echo "b64:$CLIENT82ID" >> $CLIENTOUT/groupParticipants
CLIENTCMD="timeout 360s ../bin/client group -s blob80 -l $CLIENTOUT/client80.log $CLIENTGROUPOPTS --create $CLIENTOUT/groupParticipants --message \"80 inviting 81 and 82 to new group\""
eval $CLIENTCMD > $CLIENTOUT/client80.txt 2>&1 || true &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="../bin/client group -s blob81 -l $CLIENTOUT/client81.log $CLIENTGROUPOPTS --join"
eval $CLIENTCMD > $CLIENTOUT/client81.txt 2>&1 || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
CLIENTCMD="../bin/client group -s blob82 -l $CLIENTOUT/client82.log $CLIENTGROUPOPTS --join"
eval $CLIENTCMD > $CLIENTOUT/client82.txt 2>&1 || true &
PIDVAL3=$!
echo "$CLIENTCMD -- $PIDVAL3"
wait $PIDVAL1
wait $PIDVAL2
wait $PIDVAL3

# Extract group ID -- Note to Jono this probably needs to be fixed!
GROUPID=$(cat $CLIENTOUT/client80.log | grep -a "NewGroupID\:" | awk -F' ' '{print $5}')
echo "Group ID: $GROUPID"

# Print the group list from all users
CLIENTCMD="../bin/client group -s blob80 -l $CLIENTOUT/client80.log $CLIENTGROUPOPTS --list"
eval $CLIENTCMD >> $CLIENTOUT/client80.txt 2>&1 || true &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="../bin/client group -s blob81 -l $CLIENTOUT/client81.log $CLIENTGROUPOPTS --list"
eval $CLIENTCMD >> $CLIENTOUT/client81.txt 2>&1 || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
CLIENTCMD="../bin/client group -s blob82 -l $CLIENTOUT/client82.log $CLIENTGROUPOPTS --list"
eval $CLIENTCMD >> $CLIENTOUT/client82.txt 2>&1 || true &
PIDVAL3=$!
echo "$CLIENTCMD -- $PIDVAL3"
wait $PIDVAL1
wait $PIDVAL2
wait $PIDVAL3

# Print group from all users
CLIENTCMD="../bin/client group -s blob80 -l $CLIENTOUT/client80.log $CLIENTGROUPOPTS --show $GROUPID"
eval $CLIENTCMD >> $CLIENTOUT/client80.txt 2>&1 || true &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="../bin/client group -s blob81 -l $CLIENTOUT/client81.log $CLIENTGROUPOPTS --show $GROUPID"
eval $CLIENTCMD >> $CLIENTOUT/client81.txt 2>&1 || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
CLIENTCMD="../bin/client group -s blob82 -l $CLIENTOUT/client82.log $CLIENTGROUPOPTS --show $GROUPID"
eval $CLIENTCMD >> $CLIENTOUT/client82.txt 2>&1 || true &
PIDVAL3=$!
echo "$CLIENTCMD -- $PIDVAL3"
wait $PIDVAL1
wait $PIDVAL2
wait $PIDVAL3

# Now everyone sends their message
CLIENTCMD="../bin/client group -s blob80 -l $CLIENTOUT/client80.log $CLIENTGROUPOPTS --sendMessage $GROUPID --message \"Hello from 80\""
eval $CLIENTCMD >> $CLIENTOUT/client80.txt 2>&1 || true &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="../bin/client group -s blob81 -l $CLIENTOUT/client81.log $CLIENTGROUPOPTS --sendMessage $GROUPID --message \"Hello from 81\""
eval $CLIENTCMD >> $CLIENTOUT/client81.txt 2>&1 || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
CLIENTCMD="../bin/client group -s blob82 -l $CLIENTOUT/client82.log $CLIENTGROUPOPTS --sendMessage $GROUPID --message \"Hello from 82\""
eval $CLIENTCMD >> $CLIENTOUT/client82.txt 2>&1 || true &
PIDVAL3=$!
echo "$CLIENTCMD -- $PIDVAL3"
wait $PIDVAL1
wait $PIDVAL2
wait $PIDVAL3

# Everyone waits for their message
CLIENTCMD="../bin/client group -s blob80 -l $CLIENTOUT/client80.log $CLIENTGROUPOPTS --wait 2"
eval $CLIENTCMD >> $CLIENTOUT/client80.txt 2>&1 || true &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="../bin/client group -s blob81 -l $CLIENTOUT/client81.log $CLIENTGROUPOPTS --wait 2"
eval $CLIENTCMD >> $CLIENTOUT/client81.txt 2>&1 || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
CLIENTCMD="../bin/client group -s blob82 -l $CLIENTOUT/client82.log $CLIENTGROUPOPTS --wait 2"
eval $CLIENTCMD >> $CLIENTOUT/client82.txt 2>&1 || true &
PIDVAL3=$!
echo "$CLIENTCMD -- $PIDVAL3"
wait $PIDVAL1
wait $PIDVAL2
wait $PIDVAL3

# Member 2 leaves the group
CLIENTCMD="../bin/client group -s blob81 -l $CLIENTOUT/client81.log $CLIENTGROUPOPTS --leave $GROUPID"
eval $CLIENTCMD >> $CLIENTOUT/client81.txt 2>&1 || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL2

# 1 and 3 send a message successfully now, 2 does not
CLIENTCMD="../bin/client group -s blob80 -l $CLIENTOUT/client80.log $CLIENTGROUPOPTS --sendMessage $GROUPID --message \"Hello 2 from 80\""
eval $CLIENTCMD >> $CLIENTOUT/client80.txt 2>&1 || true &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL2"
CLIENTCMD="../bin/client group -s blob82 -l $CLIENTOUT/client82.log $CLIENTGROUPOPTS --sendMessage $GROUPID --message \"Hello 2 from 82\""
eval $CLIENTCMD >> $CLIENTOUT/client82.txt 2>&1 || true &
PIDVAL3=$!
echo "$CLIENTCMD -- $PIDVAL3"
wait $PIDVAL1
wait $PIDVAL2
wait $PIDVAL3

# All 3 wait again
CLIENTCMD="../bin/client group -s blob80 -l $CLIENTOUT/client80.log $CLIENTGROUPOPTS --wait 1"
eval $CLIENTCMD >> $CLIENTOUT/client80.txt 2>&1 || true &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="../bin/client group -s blob81 -l $CLIENTOUT/client81.log $CLIENTGROUPOPTS --wait 1"
eval $CLIENTCMD >> $CLIENTOUT/client81.txt 2>&1 || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
CLIENTCMD="../bin/client group -s blob82 -l $CLIENTOUT/client82.log $CLIENTGROUPOPTS --wait 1"
eval $CLIENTCMD >> $CLIENTOUT/client82.txt 2>&1 || true &
PIDVAL3=$!
echo "$CLIENTCMD -- $PIDVAL3"
wait $PIDVAL1
wait $PIDVAL2
wait $PIDVAL3

sort -b -o "$CLIENTOUT/client80.txt" "$CLIENTOUT/client80.txt"
sort -b -o "$CLIENTOUT/client81.txt" "$CLIENTOUT/client81.txt"
sort -b -o "$CLIENTOUT/client82.txt" "$CLIENTOUT/client82.txt"

echo "GROUP CHAT FINISHED!"


echo "TESTING FILE TRANSFER..."

# Create authenticated channel between client 110 and 111
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client110.log -s blob110 --writeContact $CLIENTOUT/client110-contact.bin --unsafe -m \"Hello from contact 110 to myself, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client110.txt || true &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
wait $PIDVAL1
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client111.log -s blob111 --writeContact $CLIENTOUT/client111-contact.bin --destfile $CLIENTOUT/client110-contact.bin --send-auth-request --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client111.txt || true &
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
CLIENTCMD="timeout 360s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client110.log -s blob110 --destfile $CLIENTOUT/client111-contact.bin --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client110.txt || true &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
wait $PIDVAL1
wait $PIDVAL2

# Client 111 sends a file to client 110
CLIENTCMD="timeout 360s ../bin/client fileTransfer -s blob110 -l $CLIENTOUT/client110.log $CLIENTFILETRANSFEROPTS"
eval $CLIENTCMD > $CLIENTOUT/client110.txt 2>&1 || true &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="timeout 360s ../bin/client fileTransfer -s blob111 -l $CLIENTOUT/client111.log $CLIENTFILETRANSFEROPTS --sendFile $CLIENTOUT/client110-contact.bin --filePath LoremIpsum.txt --filePreviewString \"Lorem ipsum dolor sit amet, consectetur adipiscing elit.\" --maxThroughput 5000 --retry 0"
eval $CLIENTCMD > $CLIENTOUT/client111.txt 2>&1 || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL1
wait $PIDVAL2

echo "FILE TRANSFER FINISHED..."
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
diff -aruN $GOLDOUTPUT $CLIENTCLEAN
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
    cat $SERVERLOGS/server-*.log | grep -a "ERROR" | grep -a -v "context" | grep -av "metrics" | grep -av "database" > results/server-errors.txt || true
    cat $SERVERLOGS/server-*.log | grep -a "FATAL" | grep -a -v "context" | grep -av "transport is closing" | grep -av "database" >> results/server-errors.txt || true
    diff -aruN results/server-errors.txt noerrors.txt
    IGNOREMSG="GetRoundBufferInfo: Error received: rpc error: code = Unknown desc = round buffer is empty"
    cat $GATEWAYLOGS/*.log | grep -a "ERROR" | grep -av "context" | grep -av "certificate" | grep -av "Failed to read key" | grep -av "$IGNOREMSG" > results/gateway-errors.txt || true
    cat $GATEWAYLOGS/*.log | grep -a "FATAL" | grep -av "context" | grep -av "transport is closing" >> results/gateway-errors.txt || true
    diff -aruN results/gateway-errors.txt noerrors.txt
    echo "Checking backup files for equality..."
    diff -aruN $CLIENTOUT/client120A.backup.json $CLIENTOUT/client120B.backup.json > client120BackupDiff.txt
    diff -aruN $CLIENTOUT/client121A.backup.json $CLIENTOUT/client121B.backup.json > client121BackupDiff.txt
    diff -aruN  client120BackupDiff.txt noerrors.txt
    diff -aruN  client121BackupDiff.txt noerrors.txt
fi

echo "NO OUTPUT ERRORS, SUCCESS!"
