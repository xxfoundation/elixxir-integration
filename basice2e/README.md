= Basic End-to-End Integration Test (basice2e)

This test runs several servers and clients as a smoke test against the
system. We runs a multi node, multi message, multi user test of the
system over multiple rounds all over network traffic. The basic
structure is as follows:

* 5 Nodes, BatchSize of 12
* 3 Clients, each send 4 messages over several rounds:
** 2 messages to itself
** 1 message to each of the other nodes
* Each client asserts they receive their predefined messages

For now, we do nothing on assertion of crypto, we just assume
api-level compliance with sending and receiving messages.
