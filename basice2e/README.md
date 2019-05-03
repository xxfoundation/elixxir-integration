= Basic End-to-End Integration Test (basice2e)

This test runs several servers and clients as a smoke test against the
system. We run a multi node, multi message, multi user test of the
system over multiple rounds all over network traffic. The basic
structure is as follows:

* 5 Nodes, BatchSize of 4
* 5 Gateways, each connected to its own node
* User Discovery Bot
* Channel Bot
* Client sending 2 dummy messages per second, in order to fill batches

Then, the following tests are performed:

* 2 Clients (9 and 18) register with the system and UDB by Email
** These users look each other up on UDB
** Test is successful if the first line of gold output file matches
* The same 2 clients exchange E2E encrypted messages for 65s at a rate of 0.1msg/s
** This will result in clients sending 6 messages to each other
** It will also test that 2 rekeys on each side happen properly
** Test is successful if all the aforementioned messages are accounted for.
This is done by grep'ing the logs for sent messages, received messages, sent rekeys
and received rekeys, and comparing to gold output of 6, 6, 2, 2
* 4 Clients are started at two separate times and send messages to channel and to each other
** 2 messages to itself
** 1 message to each of the other clients
** Test is successful if all gold output files match for client conversations:
4-5, 5-6, 6-7, 7-4

For now, we do nothing on assertion of crypto, we just assume
api-level compliance with sending and receiving messages.

This test does not produce any results, but it does produce logs for each
server and client.
