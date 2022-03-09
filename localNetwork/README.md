= Local Continuously Running Network (localNetwork)

This tool runs several servers as a local simulation of the xx network. 
The basic structure is as follows:

* 3 Nodes, BatchSize of 32
* 3 Gateways, each connected to its own node
* User Discovery Bot
* Scheduling Server
* Client Registrar

With these tools you may run the xxDK off of the produced [ndf](./ndf.json), testing locally without
having to operate on MainNet or any other live network.

## Configurability

If you wish to operate with a larger local network, you may generate a programmable number of gateways/servers
using the (generate)
