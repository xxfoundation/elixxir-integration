#!/bin/bash

# This intended for updating the tested repos and their dependencies to the
# latest versions before running the integration test.

update() {
    git stash
    git clean -ffdx
    git checkout master
    git pull
    glide cc && glide up
}

for DIR in client server gateway user-discovery-bot registration; do
    echo $DIR
    pushd $GOPATH/src/gitlab.com/elixxir/client
    update
    go test ./...
    popd
done
