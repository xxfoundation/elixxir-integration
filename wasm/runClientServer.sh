#!/bin/bash

# This script starts a simple HTTP server to server Javascript clients. It also
# copies the WebAssembly binary into the server directory.

# Copy the wasm binary to the server directory
cp ../bin/xxdk.wasm clients/assets/

go run clientServer.go 9090 ./clients/