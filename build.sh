#!/bin/bash

# This intended for manually running the integration tests on your own machine
# and assumes that you've cloned the Go repos to your GOPATH and updated them
# with Glide.

pushd $GOPATH/src/gitlab.com/privategrity/client
go generate cmd/version.go
go build
popd
mv $GOPATH/src/gitlab.com/privategrity/client/client bin

pushd $GOPATH/src/gitlab.com/privategrity/server
go generate cmd/version.go
go build
popd
mv $GOPATH/src/gitlab.com/privategrity/server/server bin

pushd $GOPATH/src/gitlab.com/privategrity/channelbot
go generate cmd/version.go
go build
popd
mv $GOPATH/src/gitlab.com/privategrity/channelbot/channelbot bin

UDBPATH=gitlab.com/privategrity/user-discovery-bot
pushd $GOPATH/src/$UDBPATH
go generate cmd/version.go
popd
go build -o udb $UDBPATH
mv ./udb bin

