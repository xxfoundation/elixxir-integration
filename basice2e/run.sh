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
    echo "usage: $0 [permsip:port]"
    exit
fi


PERMISSIONING=$1

DEBUGLEVEL=${DEBUGLEVEL-0}


#export GRPC_GO_LOG_VERBOSITY_LEVEL=99
#export GRPC_GO_LOG_SEVERITY_LEVEL=info

SERVERLOGS=results/servers
GATEWAYLOGS=results/gateways
CLIENTOUT=results/clients
UDBOUT=results/udb-console.txt
CLIENTCLEAN=results/clients-cleaned

CLIENTOPTS="--password hello --ndf results/ndf.json --waitTimeout 90 --unsafe-channel-creation -v $DEBUGLEVEL"
CLIENTUDOPTS="--password hello --ndf results/ndf.json -v $DEBUGLEVEL"
CLIENTSINGLEOPTS="--password hello --ndf results/ndf.json -v $DEBUGLEVEL"

mkdir -p $SERVERLOGS
mkdir -p $GATEWAYLOGS
mkdir -p $CLIENTOUT
mkdir -p $CLIENTCLEAN

if [ "$PERMISSIONING" == "" ]
then
    echo "STARTING SERVERS..."

    UDBID=$(../bin/client init -s results/udbsession -l results/udbidgen.log --password hello --ndf ndf.json --writeContact results/udContact.bin -v $DEBUGLEVEL)
    echo "GENERATED UDB ID: $UDBID"


    PERMCMD="../bin/permissioning --logLevel $DEBUGLEVEL -c permissioning.yaml "
    $PERMCMD > results/permissioning-console.txt 2>&1 &
    PIDVAL=$!
    echo "$PERMCMD -- $PIDVAL"

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
        grep -a "RID 1 ReceiveFinishRealtime END" results/servers/server-5.log > rid.txt || true
        cnt=$(($cnt + 1))
        echo -n "."
    done

    # Start a user discovery bot server
    echo "STARTING UDB..."
    UDBCMD="../bin/udb --logLevel $DEBUGLEVEL --config udb.yaml -l 1"
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

    echo "localhost:18000" > results/permserver.txt

    echo "DONE LETS DO STUFF"

else
    echo "Connecting to network defined at $PERMISSIONING"
    echo $PERMISSIONING > results/permserver.txt
fi

echo "DOWNLOADING TLS Cert..."
openssl s_client -showcerts -connect $(cat results/permserver.txt) < /dev/null 2>&1 | openssl x509 -outform PEM > results/permcert.pem
echo "DOWNLOADING NDF..."
CLIENTCMD="../bin/client getndf --permhost $(cat results/permserver.txt) --cert results/permcert.pem"
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


if [ "$PERMISSIONING" == "" ]
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
    CLIENTCMD="timeout 240s ../bin/client  $CLIENTOPTS -l $CLIENTOUT/client9.log --sendDelay 1000 --sendCount 2 --receiveCount 2 -s blob9/blob9 --sendid 9 --destid 9 -m \"Hi 9->9, with E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client9.txt 2>&1 &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    wait $PIDVAL
    CLIENTCMD="timeout 240s ../bin/client  $CLIENTOPTS -l $CLIENTOUT/client9.log --sendDelay 1000 --sendCount 2 --receiveCount 2 -s blob9/blob9 --sendid 9 --destid 9 -m \"Hi 9->9, with E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client9.txt 2>&1 &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    wait $PIDVAL
    CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client19.log --sendDelay 1000 --sendCount 2 --receiveCount 2 -s blob19/blob19 --slowPolling --sendid 19 --destid 19 -m \"Hi 19->19, with E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client19.txt 2>&1 &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    wait $PIDVAL


    # Send E2E messages between two users
    CLIENTCMD="timeout 240s ../bin/client  $CLIENTOPTS -l $CLIENTOUT/client9.log --sendDelay 1000 --sendCount 3 --receiveCount 3 -s blob9/blob9 --sendid 9 --destid 18 -m \"Hi 9->18, with E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client9.txt 2>&1 &
    PIDVAL1=$!
    echo "$CLIENTCMD -- $PIDVAL"
    CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client18.log --sendDelay 1000  --sendCount 3 --receiveCount 3 -s blob18/blob18 --sendid 18 --destid 9 -m \"Hi 18->9, with E2E Encryption\""
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
    CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS --forceHistoricalRounds --unsafe -l $CLIENTOUT/client35.log -s blob35 --sendid 1 --destid 2 --sendCount 5 --receiveCount 5 -m \"Hello from 1, without E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client35.txt || true &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS --forceHistoricalRounds --unsafe -l $CLIENTOUT/client36.log -s blob36 --sendid 2 --destid 1 --sendCount 5 --receiveCount 5 -m \"Hello from 2, without E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client36.txt || true &
    PIDVAL2=$!
    echo "$CLIENTCMD -- $PIDVAL"
    wait $PIDVAL
    wait $PIDVAL2

    echo "FORCING MESSAGE PICKUP RETRY... (NON-E2E, PRECAN)"
    CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS --forceMessagePickupRetry --unsafe -l $CLIENTOUT/client20.log -s blob20 --sendid 20 --destid 21 --sendCount 10 --receiveCount 10 -m \"Hello from 20, without E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client20.txt || true &
    PIDVAL=$!
    echo "$CLIENTCMD -- $PIDVAL"
    CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS --forceMessagePickupRetry --unsafe -l $CLIENTOUT/client21.log -s blob21 --sendid 21 --destid 20 --sendCount 10 --receiveCount 10 -m \"Hello from 21, without E2E Encryption\""
    eval $CLIENTCMD >> $CLIENTOUT/client21.txt || true &
    PIDVAL2=$!
    echo "$CLIENTCMD -- $PIDVAL"
    wait $PIDVAL
    wait $PIDVAL2


fi

# Non-precanned E2E user messaging
echo "SENDING E2E MESSAGES TO NEW USERS..."
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blob42 --writeContact $CLIENTOUT/rick42-contact.bin --unsafe -m \"Hello from Rick42 to myself, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client42.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -s blob43 --writeContact $CLIENTOUT/ben43-contact.bin --destfile $CLIENTOUT/rick42-contact.bin --send-auth-request --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client43.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"

while [ ! -s $CLIENTOUT/ben43-contact.bin ]; do
    sleep 1
    echo -n "."
done


TMPID=$(cat $CLIENTOUT/client42.log | grep "User\:" | awk -F' ' '{print $5}')
RICKID=${TMPID}
echo "RICK ID: $RICKID"
TMPID=$(cat $CLIENTOUT/client43.log | grep "User\:" | awk -F' ' '{print $5}')
BENID=${TMPID}
echo "BEN ID: $BENID"

# Client 42 will now wait for client 43's E2E Auth channel request and confirm
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blob42 --destfile $CLIENTOUT/ben43-contact.bin --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client42.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

# Test destid syntax too, note wait for 11 messages to catch the message from above ^^^
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blob42  --destid b64:$BENID --sendCount 5 --receiveCount 5 -m \"Hello from Rick42, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client42.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -s blob43  --destid b64:$RICKID --sendCount 5 --receiveCount 5 -m \"Hello from Ben43, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client43.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blob42  --destid b64:$BENID --sendCount 5 --receiveCount 5 -m \"Hello from Rick42, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client42.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -s blob43  --destid b64:$RICKID --sendCount 5 --receiveCount 5 -m \"Hello from Ben43, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client43.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

# echo "CREATING USERS for REKEY TEST..."
# JAKEID=$(../bin/client init -s blob100 -l $CLIENTOUT/client100.log --password hello --ndf results/ndf.json --writeContact $CLIENTOUT/Jake100-contact.bin -v $DEBUGLEVEL)
# NIAMHID=$(../bin/client init -s blob101 -l $CLIENTOUT/client101.log --password hello --ndf results/ndf.json --writeContact $CLIENTOUT/Niamh101-contact.bin -v $DEBUGLEVEL)
# echo "JAKE ID: $JAKEID"
# echo "NIAMH ID: $NIAMHID"


# REKEYOPTS="--e2eMaxKeys 15 --e2eMinKeys 10 --e2eNumReKeys 5"
# # Client 101 will now send auth request
# CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS $REKEYOPTS -l $CLIENTOUT/client101.log -s blob101 --writeContact $CLIENTOUT/Niamh101-contact.bin --destfile $CLIENTOUT/Jake100-contact.bin --send-auth-request --sendCount 0 --receiveCount 0"
# eval $CLIENTCMD >> $CLIENTOUT/client101.txt || true &
# PIDVAL2=$!
# echo "$CLIENTCMD -- $PIDVAL"
# # Client 100 will now wait for client 101's E2E Auth channel request and confirm
# CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client100.log -s blob100 --destid b64:$NIAMHID --sendCount 0 --receiveCount 0"
# eval $CLIENTCMD >> $CLIENTOUT/client100.txt || true &
# PIDVAL=$!
# echo "$CLIENTCMD -- $PIDVAL"
# wait $PIDVAL
# wait $PIDVAL2

# echo "RUNNING REKEY TEST..."
# # Test destid syntax too, note wait for 11 messages to catch the message from above ^^^
# CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS $REKEYOPTS -l $CLIENTOUT/client100.log -s blob100 --destid b64:$NIAMHID --sendCount 20 --receiveCount 20 -m \"Hello from Jake100, with E2E Encryption\""
# eval $CLIENTCMD >> $CLIENTOUT/client100.txt || true &
# PIDVAL=$!
# echo "$CLIENTCMD -- $PIDVAL"
# CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS $REKEYOPTS -l $CLIENTOUT/client101.log -s blob101 --destid b64:$JAKEID --sendCount 20 --receiveCount 20 -m \"Hello from Niamh101, with E2E Encryption\""
# eval $CLIENTCMD >> $CLIENTOUT/client101.txt || true &
# PIDVAL2=$!
# echo "$CLIENTCMD -- $PIDVAL"
# wait $PIDVAL
# wait $PIDVAL2

# # Now we are just going to exhaust all the keys we have and see if we
# # use the unconfirmed channels
# CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS $REKEYOPTS -l $CLIENTOUT/client100.log -s blob100 --destid b64:$NIAMHID --sendCount 20 --receiveCount 0 -m \"Hello from Jake100, with E2E Encryption\""
# eval $CLIENTCMD >> $CLIENTOUT/client100.txt || true &
# PIDVAL=$!
# echo "$CLIENTCMD -- $PIDVAL"
# wait $PIDVAL
# # And receive those messages sent to us
# CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS $REKEYOPTS -l $CLIENTOUT/client101.log -s blob101 --destid b64:$JAKEID --sendCount 0 --receiveCount 20"
# eval $CLIENTCMD >> $CLIENTOUT/client101.txt || true &
# PIDVAL2=$!
# echo "$CLIENTCMD -- $PIDVAL"
# wait $PIDVAL2


echo "FORCING HISTORICAL ROUNDS..."
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS --forceHistoricalRounds --unsafe -l $CLIENTOUT/client35.log -s blob35 --sendid 1 --destid 2 --sendCount 5 --receiveCount 5 -m \"Hello from 1, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client35.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS --forceHistoricalRounds --unsafe -l $CLIENTOUT/client36.log -s blob36 --sendid 2 --destid 1 --sendCount 5 --receiveCount 5 -m \"Hello from 2, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client36.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

echo "FORCING MESSAGE PICKUP RETRY... "
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS --forceMessagePickupRetry -l $CLIENTOUT/client20.log -s blob20 --sendid 20 --destid 21 --sendCount 10 --receiveCount 10 -m \"Hello from 20, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client20.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 240s ../bin/client $CLIENTOPTS --forceMessagePickupRetry -l $CLIENTOUT/client21.log -s blob21 --sendid 21 --destid 20 --sendCount 10 --receiveCount 10 -m \"Hello from 21, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client21.txt || true &
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


if [ "$PERMISSIONING" == "" ]
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
fi

cp $CLIENTOUT/*.txt $CLIENTCLEAN/

sed -i.bak 's/Sending\ to\ .*\:/Sent:/g' $CLIENTCLEAN/client*.txt
sed -i.bak 's/Message\ from\ .*, .* Received:/Received:/g' $CLIENTCLEAN/client*.txt
sed -i.bak 's/ERROR.*Signature/Signature/g' $CLIENTCLEAN/client*.txt
sed -i.bak 's/[Aa]uthenticat.*$//g' $CLIENTCLEAN/client*.txt
rm $CLIENTCLEAN/client*.txt.bak

# for C in $(ls -1 $CLIENTCLEAN); do
#     sort -o tmp $CLIENTCLEAN/$C  || true
#     uniq tmp $CLIENTCLEAN/$C || true
# done

set -e


echo "TESTS EXITED SUCCESSFULLY, CHECKING OUTPUT..."
set +x
diff -aruN clients.goldoutput $CLIENTCLEAN

if [ "$PERMISSIONING" == "" ]
then

    #cat $CLIENTOUT/* | strings | grep -e "ERROR" -e "FATAL" > results/client-errors || true
    #diff -ruN results/client-errors.txt noerrors.txt
    cat $SERVERLOGS/server-*.log | grep -a "ERROR" | grep -a -v "context" | grep -av "metrics" | grep -av "database" > results/server-errors.txt || true
    cat $SERVERLOGS/server-*.log | grep -a "FATAL" | grep -a -v "context" | grep -av "transport is closing" | grep -av "database" >> results/server-errors.txt || true
    diff -aruN results/server-errors.txt noerrors.txt
    IGNOREMSG="GetRoundBufferInfo: Error received: rpc error: code = Unknown desc = round buffer is empty"
    cat $GATEWAYLOGS/*.log | grep -a "ERROR" | grep -av "context" | grep -av "certificate" | grep -av "Failed to read key" | grep -av "$IGNOREMSG" > results/gateway-errors.txt || true
    cat $GATEWAYLOGS/*.log | grep -a "FATAL" | grep -av "context" | grep -av "transport is closing" >> results/gateway-errors.txt || true
    diff -aruN results/gateway-errors.txt noerrors.txt
fi

echo "NO OUTPUT ERRORS, SUCCESS!"
