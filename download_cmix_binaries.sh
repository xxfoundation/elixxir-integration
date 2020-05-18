#!/usr/bin/env bash

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
DEFAULTBRANCH=${DEFAULTBRANCH:="release"}
REPOS_API=${REPOS_API:="https://gitlab.com/api/v4/projects/elixxir%2F"}
# Set up the gitlab access token
PATKEY=${PATKEY:="rBxQ6BvKP-eFxxeM3Ugm"}

# Make the binaries directory
download_path="$(pwd)/bin"
mkdir -p "$download_path"
# Delete old binaries
rm $download_path/*

# If we are on a feature branch, add it to the eval list
FBRANCH=$(git rev-parse --abbrev-ref HEAD)
# Also check for the branch name without the "feature" on it.
FBRANCH2=$(echo $FBRANCH | sed 's/feature\///g')

echo "Checking for binaries at $FBRANCH $FBRANCH2 $DEFAULTBRANCH..."
echo "(Note: if you forced a branch, that is checked first!)"

for BRANCH in $(echo "forcedbranch" $FBRANCH $FBRANCH2 $DEFAULTBRANCH); do
    echo $BRANCH
    BRANCH_URL=${BRANCH_URL:="jobs/artifacts/$BRANCH/raw/release"}
    echo $BRANCH_URL
    # Get URLs for artifacts from all relevant repos
    UDB_URL=${UDB_URL:="${REPOS_API}user-discovery-bot/$BRANCH_URL/udb$BIN"}
    SERVER_URL=${SERVER_URL:="${REPOS_API}server/$BRANCH_URL/server$BIN"}
    GW_URL=${GW_URL:="${REPOS_API}gateway/$BRANCH_URL/gateway$BIN"}
    PERMISSIONING_URL=${PERMISSIONING_URL:="${REPOS_API}registration/$BRANCH_URL/registration$BIN"}
    CLIENT_URL=${CLIENT_URL:="${REPOS_API}client/$BRANCH_URL/client$BIN"}
    SERVER_GPU_URL=${SERVER_GPU_URL:="${REPOS_API}server/$BRANCH_URL/server-cuda.linux64?job=build"}
    GPULIB_URL=${GPULIB_URL:="${REPOS_API}server/$BRANCH_URL/libpowmosm75.so?job=build"}

    set -x

    # Silently download the UDB binary to the provisioning directory
    if [ ! -f $download_path/udb ]; then
        curl -s -f -L -H "PRIVATE-TOKEN: $PATKEY" -o "$download_path/udb" ${UDB_URL}
    fi

    # Silently download the Server binary to the provisioning directory
    if [ ! -f $download_path/server ]; then
        curl -s -f -L -H "PRIVATE-TOKEN: $PATKEY" -o "$download_path/server" ${SERVER_URL}
    fi

    # Silently download the Gateway binary to the provisioning directory
    if [ ! -f $download_path/gateway ]; then
        curl -s -f -L -H "PRIVATE-TOKEN: $PATKEY" -o "$download_path/gateway" ${GW_URL}
    fi

    # Silently download the permissioning binary to the provisioning directory
    if [ ! -f $download_path/permissioning ]; then
        curl -s -f -L -H "PRIVATE-TOKEN: $PATKEY" -o "$download_path/permissioning" ${PERMISSIONING_URL}
    fi

    # Silently download the permissioning binary to the provisioning directory
    if [ ! -f $download_path/client ]; then
        curl -s -f -L -H "PRIVATE-TOKEN: $PATKEY" -o "$download_path/client" ${CLIENT_URL}
    fi

    # Silently download the Server binary to the provisioning directory
    if [ ! -f $download_path/server-cuda ]; then
        curl -s -f -L -H "PRIVATE-TOKEN: $PATKEY" -o "$download_path/server-cuda" ${SERVER_URL}
    fi

    # Silently download the GPU Library to the provisioning directory
    if [ ! -f $download_path/libpowmosm75.so ]; then
        curl -s -f -L -H "PRIVATE-TOKEN: $PATKEY" -o "$download_path/libpowmosm75.so" ${GPULIB_URL}
    fi

    set +x


    unset BRANCH_URL
    unset UDB_URL
    unset SERVER_URL
    unset GW_URL
    unset PERMISSIONING_URL
    unset CLIENT_URL
    unset SERVER_GPU_URL
    unset GPULIB_URL
done

# Make binaries executable
chmod +x "$download_path"/[^l]*

file "$download_path"/*

echo "If you see HTML or anything but linux/mac binaries above, something is messed up!"
