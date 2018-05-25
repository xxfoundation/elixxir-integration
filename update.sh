#!/bin/bash

# This intended for updating the tested repos and their dependencies to the
# latest versions before running the integration test.

git pull
rm -fr ~/.glide

update() {
    git clean -ffdx
#    git checkout master
    git pull
    glide cc
    glide up
}

pushd $GOPATH/src/gitlab.com/privategrity/client
update
popd

pushd $GOPATH/src/gitlab.com/privategrity/server
update
popd

pushd $GOPATH/src/gitlab.com/privategrity/channelbot
update
popd

pushd $GOPATH/src/gitlab.com/privategrity/user-discovery-bot
update
popd

pushd $GOPATH/src/gitlab.com/privategrity/gateway
update
popd

#pushd $GOPATH/src/gitlab.com/privategrity/comms
#update
#popd

#pushd $GOPATH/src/gitlab.com/privategrity/crypto
#update
#popd

#pushd $GOPATH/src/gitlab.com/privategrity/client-consoleUI
#update
#popd

pushd ..
go test ./...
popd

