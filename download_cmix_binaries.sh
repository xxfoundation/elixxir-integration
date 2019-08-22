#!/usr/bin/env bash

set -x

# Set up the URL for downloading the binaries
PRIVATEGRITY_REPOS="https://gitlab.com/api/v4/projects/elixxir%2F"
DL_URL_FRAG="jobs/artifacts/release/raw/release"
# Get URLs for artifacts from all relevant repos
SERVER_URL="${PRIVATEGRITY_REPOS}server/$DL_URL_FRAG/server.linux64?job=build"
CLIENT_URL="${PRIVATEGRITY_REPOS}client/$DL_URL_FRAG/client.linux64?job=build"
UDB_URL="${PRIVATEGRITY_REPOS}user-discovery-bot/$DL_URL_FRAG/udb.linux64?job=build"
GATEWAY_URL="${PRIVATEGRITY_REPOS}gateway/$DL_URL_FRAG/gateway.linux64?job=build"
REGISTRATION_URL="${PRIVATEGRITY_REPOS}registration/$DL_URL_FRAG/registration.linux64?job=build"
# Set up the gitlab access token
PATKEY="rBxQ6BvKP-eFxxeM3Ugm"

# Make the binaries directory
download_path="$(pwd)/bin"
mkdir -p "$download_path"

# Silently download the server binary to the provisioning directory
curl -s -f -L -H "Private-Token: $PATKEY" -o "$download_path/server" ${SERVER_URL}

# Silently download the client binary to the provisioning directory
curl -s -f -L -H "PRIVATE-TOKEN: $PATKEY" -o "$download_path/client" ${CLIENT_URL}

# Silently download the UDB binary to the provisioning directory
curl -s -f -L -H "PRIVATE-TOKEN: $PATKEY" -o "$download_path/udb" ${UDB_URL}

# Silently download the gateway binary to the provisioning directory
curl -s -f -L -H "PRIVATE-TOKEN: $PATKEY" -o "$download_path/gateway" ${GATEWAY_URL}

# Silently download the registration binary to the provisioning directory
curl -s -f -L -H "PRIVATE-TOKEN: $PATKEY" -o "$download_path/registration" ${REGISTRATION_URL}

file "$download_path"/*

echo "If you see HTML or anything but linux binaries above, something is messed up!"
