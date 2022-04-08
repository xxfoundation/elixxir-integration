#!/usr/bin/env bash

set -e

# Clear out the previous run's logs
rm gateway*-knownRound || true
rm errServer-* || true
rm *.log || true
rm roundId.txt || true
rm *-knownRound || true
rm updateId* || true
rm lastupdateid* || true
rm -r udbsession || true
rm -fr results || true
# Globals
SERVERLOGS=results/servers
GATEWAYLOGS=results/gateways
CLIENTOUT=results/clients
DUMMYOUT=results/dummy-console.txt
UDBOUT=results/udb-console.txt
mkdir -p $SERVERLOGS
mkdir -p $GATEWAYLOGS

## Uncomment to allow for verbose gRPC logs
#export GRPC_GO_LOG_VERBOSITY_LEVEL=99
#export GRPC_GO_LOG_SEVERITY_LEVEL=info


nodes=$(ls -1q ./server-*.yaml | wc -l | xargs)

BIN_PATH="../bin"
CONFIG_PATH="$(pwd)"

# Execute finish function on exit
trap finish EXIT
trap finish INT

echo "STARTING SERVERS..."

# Copy udbContact into place when running locally.
cp udbContact.bin results/udbContact.bin

# Run Permissioning
"$BIN_PATH"/permissioning \
--logLevel 2 -c "$CONFIG_PATH/permissioning-actual.yaml" &> results/registration_err.log &

echo "Permissioning: " $!

# Run Client Registrar
"$BIN_PATH"/client-registrar \
-l 2 -c "$CONFIG_PATH/client-registrar.yaml" &> results/clientRegistrar_err.log &

echo "Client Registrar: " $!

# Run server
for i in $(seq $nodes $END); do
    x=$(($i - 1))
    "$BIN_PATH"/server \
    -l 2 --config "$CONFIG_PATH/server-$x.yaml" &> $SERVERLOGS/server$x\_err.log &

    echo "Server $x: " $!
done

# Run Gateway
for i in $(seq $nodes $END); do
    x=$(($i - 1))
    "$BIN_PATH"/gateway \
    --logLevel 2 --config "$CONFIG_PATH/gateway-$x.yaml" &> $GATEWAYLOGS/gw$x\_err.log &
    PIDVAL=$!
    echo "Gateway $x -- $PIDVAL"

done

# Pipe child PIDs into file
jobs -p > results/serverpids
finish() {
    # Read in and kill all child PIDs
    # NOTE: jobs -p doesn't work in a signal handler
    echo "STOPPING SERVERS AND GATEWAYS..."
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
    set +x
}

echo "You can't use the network until rounds run."
echo "If it doesn't happen after 1 minute, please Ctrl+C"
echo "and review logs for what went wrong."
rm rid.txt || true
touch rid.txt
echo -n "Waiting for rounds to run..."
cnt=0
while [ ! -s rid.txt ] && [ $cnt -lt 240 ]; do
    sleep 1
    grep -a "RID 1 ReceiveFinishRealtime END" results/servers/*.log > rid.txt || true
    cnt=$(($cnt + 1))
    echo -n "."
done

# Run UDB
# Start a user discovery bot server
echo "STARTING UDB..."
UDBCMD="../bin/udb --logLevel 3 --config udb.yaml -l 1  --protoUserPath	udbProto.json"
$UDBCMD >> $UDBOUT 2>&1 &
echo "UDB: " $!
echo $! >> results/serverpids

echo "\nNetwork rounds have run. You may now attempt to connect."


sleep 4


echo "localhost:8200" > results/startgwserver.txt

echo "Setting up NDF for clients..."
CMD="openssl s_client -showcerts -connect $(tr -d '[:space:]' < results/startgwserver.txt)"
echo $CMD
eval $CMD < /dev/null 2>&1 > "results/startgwcert.bin"
CMD="cat results/startgwcert.bin | openssl x509 -outform PEM"
echo $CMD
eval $CMD > "results/startgwcert.pem"
head "results/startgwcert.pem"

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





# Wait until user input to exit
read -p 'Press enter to exit...'
