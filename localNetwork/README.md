# Local Continuously Running Network (localNetwork)

This tool runs several servers as a local simulation of the xx network. 
The basic structure is as follows:

* 3 cMix Nodes, BatchSize of 32
* 3 Gateways, each connected to its own node
* User Discovery Bot
* Scheduling Server
* Client Registrar

With these tools you may run the xxDK off of the produced [ndf](./ndf.json), testing locally without
having to operate on MainNet or any other live network.

## Operating the Network

To run the local network, you only need to run either `run.sh` or `runpublic.sh`. The difference
between these two scripts is described below, in the [scripts section](#scripts). Below is an example of running
`run.sh`:

```commandline
./run.sh 
rm: cannot remove 'gateway*-knownRound': No such file or directory
rm: cannot remove 'errServer-*': No such file or directory
rm: cannot remove '*.log': No such file or directory
rm: cannot remove 'roundId.txt': No such file or directory
rm: cannot remove '*-knownRound': No such file or directory
rm: cannot remove 'updateId*': No such file or directory
rm: cannot remove 'lastupdateid*': No such file or directory
rm: cannot remove 'udbsession': No such file or directory
STARTING SERVERS...
Permissioning:  112749
Client Registrar:  112750
Server 0:  112757
Server 1:  112762
Server 2:  112763
Gateway 0 -- 112774
Gateway 1 -- 112775
Gateway 2 -- 112776
You can't use the network until rounds run.
If it doesn't happen after 1 minute, please Ctrl+C
and review logs for what went wrong.
Waiting for rounds to run..............STARTING UDB...
UDB:  112937
\nNetwork rounds have run. You may now attempt to connect.
Press enter to exit... 
```

This script will run continuously until the user has sent a kill signal. The run script expects
`Enter/Return` once the network is set up. However, at any point prior of after the network is set 
up, the user may kill the script using standard kill signals (`CTR+C`, `CTR+D`, etc.).

## Scripts

### `run.sh`
The `run.sh` script  will run the network with internal IP addresses. This will allow the user
to test the xxDK from the machine running the local network.

### runpublish.sh` 
The `runpublish.sh` runs the network with remotely accessible IP addresses. This 
will allow the user to test the xxDK from another machine, provided they have passed the ndf
along.

## Configurability of Local Network

If you wish to test with a larger local network, you may use the [config file generation script](./configGen/gen.py). 
This will generate a programmable number of gateways/servers config files.
 The snippet below gives an example on how to run this script:

```commandline
$ cd configGen/
$  python3 gen.py 
Total number of nodes: 9
Minimum number of nodes online to start network: 3
Size of each team: 3
```

This example generates 9 cMix nodes with 9 associated gateways. The rounds will have 3 nodes in a team,
and the network only needs 3 nodes running to start running rounds. 

Once config files have been generated, you need only execute the run script to run a network of the desired size
and specifications. Please note that this network does run locally, and as such larger networks
may be resource intensive (depending on the user's machine).
