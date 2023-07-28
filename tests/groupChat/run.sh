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

GROUPRESULTS=$1
GOLDOUTPUT=$2
NDF=$3

DEBUGLEVEL=${DEBUGLEVEL-1}

CLIENTOUT=$GROUPRESULTS/clients
CLIENTCLEAN=$GROUPRESULTS/clients-cleaned

mkdir -p $CLIENTOUT
mkdir -p $CLIENTCLEAN

#export GRPC_GO_LOG_VERBOSITY_LEVEL=99
#export GRPC_GO_LOG_SEVERITY_LEVEL=info

###############################################################################
# Test  Group Chat
###############################################################################

CLIENTOPTS="--password hello --ndf $NDF --verify-sends --sendDelay 100 --waitTimeout 360 -v $DEBUGLEVEL"
CLIENTGROUPOPTS="--password hello --waitTimeout 600 --ndf $NDF -v $DEBUGLEVEL"

echo "TESTING GROUP CHAT..."
# Create authenticated channel between client 80 and 81
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS -l $CLIENTOUT/client80.log -s blobs/80 --writeContact $CLIENTOUT/client80-contact.bin --unsafe -m \"Hello from contact 80 to myself, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client80.txt &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
wait $PIDVAL1
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS -l $CLIENTOUT/client81.log -s blobs/81 --writeContact $CLIENTOUT/client81-contact.bin --destfile $CLIENTOUT/client80-contact.bin --send-auth-request --unsafe-channel-creation --sendCount 0 --receiveCount 0"
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
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS -l $CLIENTOUT/client80.log -s blobs/80 --destfile $CLIENTOUT/client81-contact.bin --sendCount 0 --receiveCount 0 --accept-channel --auth-timeout 360"
eval $CLIENTCMD >> $CLIENTOUT/client80.txt &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
wait $PIDVAL1
wait $PIDVAL2


# Create authenticated channel between client 80 and 82
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS -l $CLIENTOUT/client82.log -s blobs/82 --writeContact $CLIENTOUT/client82-contact.bin --destfile $CLIENTOUT/client80-contact.bin --send-auth-request --unsafe-channel-creation --sendCount 0 --receiveCount 0"
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
CLIENTCMD="timeout 240s bin/client $CLIENTOPTS -l $CLIENTOUT/client80.log -s blobs/80 --destfile $CLIENTOUT/client82-contact.bin --sendCount 0 --receiveCount 0 --accept-channel --auth-timeout 360"
eval $CLIENTCMD >> $CLIENTOUT/client80.txt &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
wait $PIDVAL1
wait $PIDVAL3

# User 1 Creates Group
echo "Group User IDs: $CLIENT80ID $CLIENT81ID $CLIENT82ID"
echo "b64:$CLIENT81ID" > $CLIENTOUT/groupParticipants
echo "b64:$CLIENT82ID" >> $CLIENTOUT/groupParticipants
CLIENTCMD="timeout 605s bin/client group -s blobs/80 -l $CLIENTOUT/client80.log $CLIENTGROUPOPTS --create $CLIENTOUT/groupParticipants --message \"80 inviting 81 and 82 to new group\""
eval $CLIENTCMD > $CLIENTOUT/client80.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="bin/client group -s blobs/81 -l $CLIENTOUT/client81.log $CLIENTGROUPOPTS --join"
eval $CLIENTCMD > $CLIENTOUT/client81.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
CLIENTCMD="bin/client group -s blobs/82 -l $CLIENTOUT/client82.log $CLIENTGROUPOPTS --join"
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
CLIENTCMD="bin/client group -s blobs/80 -l $CLIENTOUT/client80.log $CLIENTGROUPOPTS --list"
eval $CLIENTCMD >> $CLIENTOUT/client80.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="bin/client group -s blobs/81 -l $CLIENTOUT/client81.log $CLIENTGROUPOPTS --list"
eval $CLIENTCMD >> $CLIENTOUT/client81.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
CLIENTCMD="bin/client group -s blobs/82 -l $CLIENTOUT/client82.log $CLIENTGROUPOPTS --list"
eval $CLIENTCMD >> $CLIENTOUT/client82.txt 2>&1 &
PIDVAL3=$!
echo "$CLIENTCMD -- $PIDVAL3"
wait $PIDVAL1
wait $PIDVAL2
wait $PIDVAL3

# Print group from all users
CLIENTCMD="bin/client group -s blobs/80 -l $CLIENTOUT/client80.log $CLIENTGROUPOPTS --show $GROUPID"
eval $CLIENTCMD >> $CLIENTOUT/client80.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="bin/client group -s blobs/81 -l $CLIENTOUT/client81.log $CLIENTGROUPOPTS --show $GROUPID"
eval $CLIENTCMD >> $CLIENTOUT/client81.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
CLIENTCMD="bin/client group -s blobs/82 -l $CLIENTOUT/client82.log $CLIENTGROUPOPTS --show $GROUPID"
eval $CLIENTCMD >> $CLIENTOUT/client82.txt 2>&1 &
PIDVAL3=$!
echo "$CLIENTCMD -- $PIDVAL3"
wait $PIDVAL1
wait $PIDVAL2
wait $PIDVAL3

# Now everyone sends their message
CLIENTCMD="bin/client group -s blobs/80 -l $CLIENTOUT/client80.log $CLIENTGROUPOPTS --sendMessage $GROUPID --message \"Hello from 80\""
eval $CLIENTCMD >> $CLIENTOUT/client80.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="bin/client group -s blobs/81 -l $CLIENTOUT/client81.log $CLIENTGROUPOPTS --sendMessage $GROUPID --message \"Hello from 81\""
eval $CLIENTCMD >> $CLIENTOUT/client81.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
CLIENTCMD="bin/client group -s blobs/82 -l $CLIENTOUT/client82.log $CLIENTGROUPOPTS --sendMessage $GROUPID --message \"Hello from 82\""
eval $CLIENTCMD >> $CLIENTOUT/client82.txt 2>&1 &
PIDVAL3=$!
echo "$CLIENTCMD -- $PIDVAL3"
wait $PIDVAL1
wait $PIDVAL2
wait $PIDVAL3

# Everyone waits for their message
CLIENTCMD="bin/client group -s blobs/80 -l $CLIENTOUT/client80.log $CLIENTGROUPOPTS --wait 2"
eval $CLIENTCMD >> $CLIENTOUT/client80.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="bin/client group -s blobs/81 -l $CLIENTOUT/client81.log $CLIENTGROUPOPTS --wait 2"
eval $CLIENTCMD >> $CLIENTOUT/client81.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
CLIENTCMD="bin/client group -s blobs/82 -l $CLIENTOUT/client82.log $CLIENTGROUPOPTS --wait 2"
eval $CLIENTCMD >> $CLIENTOUT/client82.txt 2>&1 &
PIDVAL3=$!
echo "$CLIENTCMD -- $PIDVAL3"
wait $PIDVAL1
wait $PIDVAL2
wait $PIDVAL3

# Member 2 leaves the group
CLIENTCMD="bin/client group -s blobs/81 -l $CLIENTOUT/client81.log $CLIENTGROUPOPTS --leave $GROUPID"
eval $CLIENTCMD >> $CLIENTOUT/client81.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
wait $PIDVAL2

# 1 and 3 send a message successfully now, 2 does not
CLIENTCMD="bin/client group -s blobs/80 -l $CLIENTOUT/client80.log $CLIENTGROUPOPTS --sendMessage $GROUPID --message \"Hello 2 from 80\""
eval $CLIENTCMD >> $CLIENTOUT/client80.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL2"
CLIENTCMD="bin/client group -s blobs/82 -l $CLIENTOUT/client82.log $CLIENTGROUPOPTS --sendMessage $GROUPID --message \"Hello 2 from 82\""
eval $CLIENTCMD >> $CLIENTOUT/client82.txt 2>&1 &
PIDVAL3=$!
echo "$CLIENTCMD -- $PIDVAL3"
wait $PIDVAL1
wait $PIDVAL2
wait $PIDVAL3

# All 3 wait again
CLIENTCMD="bin/client group -s blobs/80 -l $CLIENTOUT/client80.log $CLIENTGROUPOPTS --wait 1"
eval $CLIENTCMD >> $CLIENTOUT/client80.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL1"
CLIENTCMD="bin/client group -s blobs/81 -l $CLIENTOUT/client81.log $CLIENTGROUPOPTS --wait 1"
eval $CLIENTCMD >> $CLIENTOUT/client81.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL2"
CLIENTCMD="bin/client group -s blobs/82 -l $CLIENTOUT/client82.log $CLIENTGROUPOPTS --wait 1"
eval $CLIENTCMD >> $CLIENTOUT/client82.txt 2>&1 &
PIDVAL3=$!
echo "$CLIENTCMD -- $PIDVAL3"
wait $PIDVAL1
wait $PIDVAL2
wait $PIDVAL3

echo "GROUP CHAT FINISHED!"
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
