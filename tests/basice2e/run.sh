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

BASICE2ERESULTS=$1
GOLDOUTPUT=$2
NDF=$3

DEBUGLEVEL=${DEBUGLEVEL-1}

CLIENTOUT=$BASICE2ERESULTS/clients
CLIENTCLEAN=$BASICE2ERESULTS/clients-cleaned

mkdir -p $CLIENTOUT
mkdir -p $CLIENTCLEAN


#export GRPC_GO_LOG_VERBOSITY_LEVEL=99
#export GRPC_GO_LOG_SEVERITY_LEVEL=info

CLIENTOPTS="--password hello --ndf $NDF --verify-sends --sendDelay 100 --waitTimeout 360 -v $DEBUGLEVEL"
CLIENTREKEYOPTS="--password hello --ndf $NDF --verify-sends --waitTimeout 600 -v $DEBUGLEVEL"

###############################################################################
# Test  Sending E2E
###############################################################################

# Non-precanned E2E user messaging
echo "SENDING E2E MESSAGES TO NEW USERS..."
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blobs/42 --writeContact $CLIENTOUT/rick42-contact.bin --unsafe -m \"Hello from Rick42 to myself, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client42.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -s blobs/43 --writeContact $CLIENTOUT/ben43-contact.bin --destfile $CLIENTOUT/rick42-contact.bin --send-auth-request --unsafe-channel-creation --sendCount 0 --receiveCount 0"
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
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blobs/42 --destfile $CLIENTOUT/ben43-contact.bin --sendCount 0 --receiveCount 0 --accept-channel --auth-timeout 360"
eval $CLIENTCMD >> $CLIENTOUT/client42.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

# Test destid syntax too, note wait for 11 messages to catch the message from above ^^^
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blobs/42  --destid b64:$BENID --sendCount 5 --receiveCount 5 -m \"Hello from Rick42, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client42.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -s blobs/43  --destid b64:$RICKID --sendCount 5 --receiveCount 5 -m \"Hello from Ben43, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client43.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blobs/42  --destid b64:$BENID --sendCount 5 --receiveCount 5 -m \"Hello from Rick42, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client42.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -s blobs/43  --destid b64:$RICKID --sendCount 5 --receiveCount 5 -m \"Hello from Ben43, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client43.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

###############################################################################
# Test  Renegotiation
###############################################################################

echo "TESTING RENEGOTIATION..."
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -s blobs/43 --destfile $CLIENTOUT/rick42-contact.bin --send-auth-request  --unsafe-channel-creation --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client43.txt &
PIDVAL1=$!
# Unlike before, we don't accept the channel (it's already been accepted, it'll
# renegotiate), so instead we message ourselves to wait for the trigger
echo "$CLIENTCMD -- $PIDVAL1"
# Client 42 will now wait, again, for client 43's E2E Auth channel request and confirm
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blobs/42 --destfile $CLIENTOUT/rick42-contact.bin --sendCount 10 --receiveCount 10 --unsafe -m \"Waiting on renegotiation\""
eval $CLIENTCMD >> $CLIENTOUT/client42.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL1
wait $PIDVAL2
#Send a few messages
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blobs/42  --destid b64:$BENID --sendCount 5 --receiveCount 5 -m \"Hello from Rick42, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client42.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -s blobs/43  --destid b64:$RICKID --sendCount 5 --receiveCount 5 -m \"Hello from Ben43, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client43.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL
wait $PIDVAL2

echo "SWITCHING RENEGOTIATION TEST..."
# Switch places, 42 renegotiates with 43
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blobs/42 --destfile $CLIENTOUT/ben43-contact.bin --send-auth-request  --unsafe-channel-creation --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client42.txt &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
# Client 43 will now wait, for client 42's renegotiated E2E Auth channel request and confirm
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -s blobs/43 --destfile $CLIENTOUT/ben43-contact.bin --sendCount 10 --receiveCount 10 --unsafe -m \"Waiting on switching renegotiation\""
eval $CLIENTCMD >> $CLIENTOUT/client43.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL1
wait $PIDVAL2
#Send a few more messages
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blobs/42  --destid b64:$BENID --sendCount 5 --receiveCount 5 -m \"Hello from Rick42, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client42.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -s blobs/43  --destid b64:$RICKID --sendCount 5 --receiveCount 5 -m \"Hello from Ben43, with E2E Encryption\""
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
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blobs/42 --delete-channel --destfile $CLIENTOUT/ben43-contact.bin --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client42.txt &
echo "$CLIENTCMD -- $PIDVAL"
PIDVAL1=$!
wait $PIDVAL1
# NOTE the command below causes the following EXPECTED error:
# panic: Could not confirm authentication channel for HTAmEeBhbLi6aFqcWsi3OZNDE/642GAchpATjhYFTHwD, waited 120 seconds.
# Note that the above is example, client IDs will vary
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blobs/42  --destid b64:$BENID --sendCount 5 --receiveCount 5 -m \"Hello from Rick42, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client42.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
echo "NOTE: The command above causes an EXPECTED failure to confirm authentication channel!"
wait $PIDVAL2

echo "DELETING REQUESTS FROM CLIENT.."
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client44.log -s blobs/44 --writeContact $CLIENTOUT/david44-contact.bin --unsafe -m \"Hello from David44 to myself, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client44.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

# NOTE: client45 is a precan user (see runclients), so we skip to 46 here.
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client46.log -s blobs/46 --writeContact $CLIENTOUT/matt46-contact.bin --destfile $CLIENTOUT/david44-contact.bin  --unsafe-channel-creation --send-auth-request --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client46.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL2

CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client46.log -s blobs/46 --delete-sent-requests --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client46.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL2

# This is tricky -- we've deleted the request without having received the
# confirmation, so now the receiver attempts to accept the channel while the
# sender (without confirmation) sends to them without an auth channel.
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client44.log -s blobs/44 --destfile $CLIENTOUT/matt46-contact.bin --sendCount 0 --receiveCount 0 --accept-channel --auth-timeout 360"
eval $CLIENTCMD >> $CLIENTOUT/client44.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS -l $CLIENTOUT/client46.log -s blobs/46  --destfile $CLIENTOUT/david44-contact.bin --sendCount 5 --receiveCount 5 -m \"Hello from David, with E2E Encryption\""
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
JONOID=$(bin/client init -s blobs/85 -l $CLIENTOUT/client85.log --password hello --ndf $NDF --writeContact $CLIENTOUT/jono85-contact.bin -v $DEBUGLEVEL)
SYDNEYID=$(bin/client init -s blobs/86 -l $CLIENTOUT/client86.log --password hello --ndf $NDF --writeContact $CLIENTOUT/sydney86-contact.bin -v $DEBUGLEVEL)
echo "JONO ID: $JONOID"
echo "SYDNEY ID: $SYDNEYID"

# Attempt to send an auth request at the same time. It's not guaranteed that
# one side won't send and the other won't receive before sending their request
# but this method has proven to be reasonably reliable.
echo "STARTING SIMULTANEOUSAUTH TEST..."
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client85.log -s blobs/85 --destfile $CLIENTOUT/sydney86-contact.bin --unsafe-channel-creation --send-auth-request --unsafe-channel-creation --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client85.txt &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client86.log -s blobs/86 --destfile $CLIENTOUT/jono85-contact.bin --unsafe-channel-creation --send-auth-request --unsafe-channel-creation --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client86.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL1
wait $PIDVAL2

# Send a couple messages
echo "TESTING SIMULTANEOUSAUTH MESSAGE SEND..."
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client85.log -s blobs/85 --destfile $CLIENTOUT/sydney86-contact.bin --sendCount 5 --receiveCount 5 -m \"Hello Sydney from Jono, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client85.txt &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="timeout 360s bin/client $CLIENTOPTS -l $CLIENTOUT/client86.log -s blobs/86 --destfile $CLIENTOUT/jono85-contact.bin --sendCount 5 --receiveCount 5 -m \"Hello Jono from Sydney, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client86.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL1
wait $PIDVAL2

###############################################################################
# Test  Proto User
###############################################################################

# Proto user test: client25 and client26 generate a proto user JSON file and close.
# Both clients are restarted and load from their respective proto user files and attempt to send.

# Generate contact and proto user file for client25
echo "TESTING PROTO USER FILE..."

CLIENTCMD="timeout 60s bin/client -l $CLIENTOUT/client25.log -s blobs/11420 --password hello --ndf $NDF --writeContact $CLIENTOUT/josh25-contact.bin --protoUserOut $CLIENTOUT/client25Proto.json --unsafe --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client25.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

# Generate contact and proto user file for client 26
CLIENTCMD="timeout 60s bin/client -l $CLIENTOUT/client26.log -s blobs/11421 --password hello --ndf $NDF --writeContact $CLIENTOUT/jonah26-contact.bin --protoUserOut $CLIENTOUT/client26Proto.json --unsafe --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client26.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

# Clients will now load from the protoUser file and write to session
CLIENTCMD="timeout 60s bin/client $CLIENTOPTS -l $CLIENTOUT/client25.log -s blobs/25  --protoUserPath $CLIENTOUT/client25Proto.json --unsafe --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client25.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 60s bin/client $CLIENTOPTS -l $CLIENTOUT/client26.log -s blobs/26  --protoUserPath $CLIENTOUT/client26Proto.json --unsafe --sendCount 0 --receiveCount 0"
eval $CLIENTCMD >> $CLIENTOUT/client26.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL
wait $PIDVAL2

# Continue with E2E testing with session files loaded from proto
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS -l $CLIENTOUT/client25.log -s blobs/25 --writeContact $CLIENTOUT/josh25-contact.bin --unsafe -m \"Hello from Josh25 to myself, without E2E Encryption\" "
eval $CLIENTCMD >> $CLIENTOUT/client25.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS -l $CLIENTOUT/client26.log -s blobs/26 --writeContact $CLIENTOUT/jonah26-contact.bin --destfile $CLIENTOUT/josh25-contact.bin  --unsafe-channel-creation --send-auth-request --sendCount 0 --receiveCount 0"
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
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS -l $CLIENTOUT/client25.log -s blobs/25 --destfile $CLIENTOUT/jonah26-contact.bin --sendCount 0 --receiveCount 0 --accept-channel --auth-timeout 360"
eval $CLIENTCMD >> $CLIENTOUT/client25.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

# Send E2E messages with written sessions
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS -l $CLIENTOUT/client25.log -s blobs/25 --destid b64:$JONAHID --sendCount 5 --receiveCount 5 -m \"Hello from Josh25, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client25.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS -l $CLIENTOUT/client26.log -s blobs/26  --destid b64:$JOSHID --sendCount 5 --receiveCount 5 -m \"Hello from Jonah26, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client26.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS -l $CLIENTOUT/client25.log -s blobs/25 --destid b64:$JONAHID --sendCount 5 --receiveCount 5 -m \"Hello from Josh25, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client25.txt &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS -l $CLIENTOUT/client26.log -s blobs/26 --destid b64:$JOSHID --sendCount 5 --receiveCount 5 -m \"Hello from Jonah26, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client26.txt &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

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

set +x
diff -aru $GOLDOUTPUT $CLIENTCLEAN
cat $CLIENTOUT/client42.log | grep -a "Could not confirm authentication channel" > $CLIENTOUT/deleteContact.txt || true
echo "CHECKING FOR SUCCESSFUL CONTACT DELETION"
if [ -s $CLIENTOUT/deleteContact.txt ]
then
    echo "CONTACT DELETION SUCCESSFUL"
else
    echo "CONTACT DELETION FAILED"
    [ -s $CLIENTOUT/deleteContact.txt ]
fi

echo "NO OUTPUT ERRORS, SUCCESS!"
