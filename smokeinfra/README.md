= Smoke Infrastructure Test (smokeinfra)

This test runs 3 servers and gateways as a smoke test against the
system infrastructure. Details are:

* 3 Nodes, BatchSize of 42
* 3 Gateways, each connected to its own node

This test does not produce any results, but it does produce logs for each
server and client.

The test passes when gateways and servers are killed without errors. Otherwise
every console log is tail'd for diagnostic output.
