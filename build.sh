#!/bin/bash

# This intended for manually running the integration tests on your own machine
# and assumes that you've cloned the Go repos to your GOPATH and updated them
# with Glide.

mkdir -p bin

build() {
    #go generate cmd/version.go
    go build
}

pushd $GOPATH/src/gitlab.com/elixxir/client
build
popd
mv $GOPATH/src/gitlab.com/elixxir/client/client bin

pushd $GOPATH/src/gitlab.com/elixxir/server
build
popd
mv $GOPATH/src/gitlab.com/elixxir/server/server bin

pushd $GOPATH/src/gitlab.com/elixxir/channelbot
build
popd
mv $GOPATH/src/gitlab.com/elixxir/channelbot/channelbot bin

UDBPATH=gitlab.com/elixxir/user-discovery-bot
pushd $GOPATH/src/$UDBPATH
#go generate cmd/version.go
popd
go build -o udb $UDBPATH
mv ./udb bin

pushd $GOPATH/src/gitlab.com/elixxir/gateway
build
popd
mv $GOPATH/src/gitlab.com/elixxir/gateway/gateway bin
