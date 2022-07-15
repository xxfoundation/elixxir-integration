set -e

#echo Initialization Upgrade
#OLDCLIENT="client-release" OLDDIVISE=2 ./run.sh > init-upgrade.txt 2>&1

#echo Initialization Cross-Version
#OLDCLIENT="client-release" OLDDIVISE=0 ./run.sh > init-cross-version.txt 2>&1

echo Upgraded Messaging pass 1
./run.sh > messaging-upgraded-pass1.txt 2>&1
echo Upgraded Messaging pass 2
CLIENTSUFFIX="-release" SKIPCLEAN=1 EXTRACLIENTFLAGS="--force-legacy" ./run.sh > messaging-upgraded-pass2.txt 2>&1

echo Cross-Version Messaging pass 1
./run.sh > messaging-cross-pass1.txt 2>&1
echo Cross-Version Messaging pass 2
CLIENTSUFFIX="-release" SKIPCLEAN=1 CLIENTTWO="client-release" ./run.sh > messaging-cross-pass2.txt 2>&1

echo Cross-Version Full
CLIENTTWO="client-release" ./run.sh > full-crossversion.txt 2>&1 