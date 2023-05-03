NETRESULTS=$1/network

finish() {
    echo "STOPPING SERVERS AND GATEWAYS..."
    if [ -n "$NSYSENABLED" ]
    then
        nsys stop --session=gputest
    fi
    # NOTE: jobs -p doesn't work in a signal handler
    for job in $(cat $NETRESULTS/serverpids)
    do
        echo "KILLING $job"
        kill $job || true
    done

    sleep 5

    for job in $(cat $NETRESULTS/serverpids)
    do
        echo "KILL -9 $job"
        kill -9 $job || true
    done
    rm -f $NETRESULTS/serverpids
    #tail $SERVERLOGS/*
    #tail $CLIENTCLEAN/*
    #diff -aruN clients.goldoutput $CLIENTCLEAN

    #cat $CLIENTOUT/* | strings | grep -ae "ERROR" -e "FATAL" > results/client-errors || true
    #diff -ruN results/client-errors.txt noerrors.txt
    cat $SERVERLOGS/server-*.log | grep -a "ERROR" | grep -a -v "context" | grep -av "metrics" | grep -av "database" | grep -av RequestClientKey > $NETRESULTS/server-errors.txt || true
    cat $SERVERLOGS/server-*.log | grep -a "FATAL" | grep -a -v "context" | grep -av "transport is closing" | grep -av "database" >> $NETRESULTS/server-errors.txt || true
    diff -aruN $NETRESULTS/server-errors.txt noerrors.txt
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
}
