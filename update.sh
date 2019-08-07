#!/bin/bash

# This intended for updating the tested repos and their dependencies to the
# latest versions before running the integration test. All runtime options are
# set via environemnt variables:
#   defaultBranch     sets branch to use for all projects
#   clientBranch      sets branch to use for the client repository
#   serverBranch      sets branch to use for the server repository
#   gatewayBranch     sets branch to use for the gateway repository
#   udbBranch         sets branch to use for the user-discovery-bot repository
#   regBranch         sets branch to use for the registration repository

# Default branch to use when no explicit project branch is set. If not set, then
# it defaults to "master".
default="${defaultBranch-"master"}"

# Array of project names.
project_arr=(
  client
  server
  gateway
  user-discovery-bot
  registration
)

# Array of each project's branch. If a branch is not explicitly set via an
# environemnt variable, then it defaults to defaultBranch.
branch_arr=(
  "${clientBranch-$default}"
  "${serverBranch-$default}"
  "${gatewayBranch-$default}"
  "${udbBranch-$default}"
  "${regBranch-$default}"
)

update() {
    git stash
    git clean -ffdx
    git checkout "$1"
    git pull
    glide cache-clear && glide update
}

for ((i=0; i<${#project_arr[@]}; ++i)); do
    printf "\n%s\n" "${project_arr[i]}"
    pushd "$GOPATH"/src/gitlab.com/elixxir/client || exit
    update "${branch_arr[i]}"
    go test ./...
    popd || exit
done
