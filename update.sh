#!/bin/bash

# This intended for updating the tested repos and their dependencies to the
# latest versions before running the integration test.

git pull
rm -fr ~/.glide

pushd $GOPATH/src/gitlab.com/privategrity/client
git clean -ffdx
git pull
glide cc
glide up
popd

pushd $GOPATH/src/gitlab.com/privategrity/server
git clean -ffdx
git pull
glide cc
glide up
popd

pushd $GOPATH/src/gitlab.com/privategrity/channelbot
git clean -ffdx
git pull
glide cc
glide up
popd

pushd $GOPATH/src/gitlab.com/privategrity/user-discovery-bot
git clean -ffdx
git pull
glide cc
glide up
popd
