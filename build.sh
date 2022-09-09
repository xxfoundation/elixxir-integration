#!/bin/bash

# This intended for manually running the integration tests on your own machine
# and assumes that you've cloned the Go repos to your GOPATH and updated them
# with Glide.

set -x
mkdir -p bin
pushd bin
OUT=$PWD
pushd gitlab.com/elixxir/client && go build -o $OUT/client main.go && popd
pushd gitlab.com/elixxir/user-discovery-bot && go build -o $OUT/udb main.go && popd
pushd gitlab.com/elixxir/registration && go build -o $OUT/permissioning main.go && popd
pushd gitlab.com/elixxir/client-registrar && go build -o $OUT/client-registrar main.go && popd
pushd gitlab.com/elixxir/gateway && go build -o $OUT/gateway main.go && popd
pushd gitlab.com/elixxir/server && go build -o $OUT/server main.go && popd
popd
