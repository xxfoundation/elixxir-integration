#!/usr/bin/env bash

set -x

# Get platform parameter
if [[ $1 == "l" ]] ||[[ $1 == "linux" ]] || [[ -z $1 ]]; then
    BIN=".linux64?job=build"
    echo "Platform set to Linux"
elif [[ $1 == "m" ]] || [[ $1 == "mac" ]]; then
    BIN=".darwin64?job=build"
    echo "Platform set to Mac"
else
    echo "Invalid platform argument: $1"
    exit 0
fi

# Set up the URL for downloading the binaries
PRIVATEGRITY_REPOS="https://gitlab.com/api/v4/projects/elixxir%2F"
MASTER_URL_FRAG="jobs/artifacts/release/raw/release"

# Get URLs for artifacts from all relevant repos
UDB_URL="${PRIVATEGRITY_REPOS}user-discovery-bot/$MASTER_URL_FRAG/udb$BIN"
SERVER_URL="${PRIVATEGRITY_REPOS}server/$MASTER_URL_FRAG/server$BIN"
GW_URL="${PRIVATEGRITY_REPOS}gateway/$MASTER_URL_FRAG/gateway$BIN"
PERMISSIONING_URL="${PRIVATEGRITY_REPOS}registration/$MASTER_URL_FRAG/registration$BIN"

# Set up the gitlab access token
PATKEY="rBxQ6BvKP-eFxxeM3Ugm"

# Make the binaries directory
download_path="$(pwd)/bin"
mkdir -p "$download_path"

# Silently download the UDB binary to the provisioning directory
curl -s -f -L -H "PRIVATE-TOKEN: $PATKEY" -o "$download_path/udb" ${UDB_URL}

# Silently download the Server binary to the provisioning directory
curl -s -f -L -H "PRIVATE-TOKEN: $PATKEY" -o "$download_path/server" ${SERVER_URL}

# Silently download the Gateway binary to the provisioning directory
curl -s -f -L -H "PRIVATE-TOKEN: $PATKEY" -o "$download_path/gateway" ${GW_URL}

# Silently download the permissioning binary to the provisioning directory
curl -s -f -L -H "PRIVATE-TOKEN: $PATKEY" -o "$download_path/permissioning" ${PERMISSIONING_URL}

# Make binaries executable
chmod +x "$download_path"/*.binary

file "$download_path"/*

echo "If you see HTML or anything but linux binaries above, something is messed up!"
