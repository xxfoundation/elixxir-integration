# SendE2E Test

This test sets up two clients in the browser and has one client send an E2E
message to the other.

## Running the Test

1. First, compile the WASM binary and start the local HTTP server. Refer to wasm
   test [README](../README.md) for details on how to do this. Open the two
   clients, the sender and receiver.

2. Next, start the network using the `run.sh` script. This will start all the
   gateways and client registrar using localhost as their public IP addresses
   and the NDF will be provided by the permissioning server rather than
   downloaded from a gateway.

3. Once rounds are running, on the receiver webpage, navigate to the results
   folder in integration and select the `permissions-ndfoutput.json` file. Doing
   this will start the client. Once the client generates keys and joins the
   network, it will prompt its contact file for download. Copy the contents of
   this file into the `recipientContactFile` const in `sender.html`.

4. On the sender webpage (make sure to refresh the page), select the NDF file as
   described for the recipient above. This will start the sender client. Once it
   generates its keys and joins the network, it will add the receiver client as
   a partner, they will exchange requests and confirmations, and finally, the
   sender will send an E2E message to the recipient.