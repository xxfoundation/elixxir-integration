#!/bin/bash

# This intended for updating the tested repos and their dependencies to the
# latest versions before running the integration test.

git pull
rm -fr ~/.glide

update() {
    git stash
    git clean -ffdx
    git checkout master
    git pull
    glide cc
    glide up
}

pushd $GOPATH/src/gitlab.com/elixxir/client
update
popd

pushd $GOPATH/src/gitlab.com/elixxir/server
update
popd

pushd $GOPATH/src/gitlab.com/elixxir/channelbot
update
popd

pushd $GOPATH/src/gitlab.com/elixxir/user-discovery-bot
update
popd

pushd $GOPATH/src/gitlab.com/elixxir/gateway
update
popd

pushd $GOPATH/src/gitlab.com/elixxir/comms
update
popd

pushd $GOPATH/src/gitlab.com/elixxir/crypto
update
popd

pushd $GOPATH/src/gitlab.com/elixxir/client-consoleUI
update
popd

pushd ..
go test ./...
popd

