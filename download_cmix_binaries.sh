#!/usr/bin/env bash


# DEFAULTS FOR INTEGRATION -- do not publish
if [ "$GITLAB_ACCESS_TOKEN" == "" ]
then
    echo "ERROR: SET GITLAB_ACCESS_TOKEN in your environment"
    exit -1
fi

PLATFORM=$1
USEREPO=$2

if [ "$PLATFORM" == "" ]
then
    PLATFORM="l"
fi

if [ "$USEREPO" == "" ]
then
    USEREPO="d"
fi

# Get platform parameter
# === LINUX ===
if [[ $PLATFORM == "l" ]] ||[[ $PLATFORM == "linux" ]] || [[ -z $PLATFORM ]]; then
    if [[ $USEREPO == "d" ]]; then
        BIN=".linux64?job=build"
    else
        BIN=".linux64"
    fi
    echo "Platform set to Linux"

    # === MACOS ===
elif [[ $PLATFORM == "m" ]] || [[ $PLATFORM == "mac" ]]; then

    if [[ $USEREPO == "d" ]]; then
        BIN=".darwin64?job=build"
    else
        BIN=".darwin64"
    fi
    echo "Platform set to Mac"

else
    echo "Invalid platform argument: $PLATFORM"
    exit 0
fi

# Set up the URL for downloading the binaries
DEFAULTBRANCH=${DEFAULTBRANCH:="release"}
if [[ $USEREPO == "d" ]]; then
    REPOS_API=${REPOS_API:="https://git.xx.network/api/v4/projects/elixxir%2F"}
else
    REPOS_API=${REPOS_API:="https://elixxir-bins.s3-us-west-1.amazonaws.com"}
fi

# Make the binaries directory
download_path="$(pwd)/bin"
mkdir -p "$download_path"
# Delete old binaries
rm $download_path/*

# If we are on a feature branch, add it to the eval list
FBRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CI_BUILD_REF_NAME" != "" ]]; then
    FBRANCH=$CI_BUILD_REF_NAME
fi
FBRANCH=$(echo $FBRANCH | grep feature)
# Also check for the branch name without the "feature" on it.
FBRANCH2=$(echo $FBRANCH | sed 's/feature\///g')

echo "Checking for binaries at $FBRANCH $FBRANCH2 $DEFAULTBRANCH..."
echo "(Note: if you forced a branch, that is checked first!)"

for BRANCH in $(echo "forcedbranch" $FBRANCH $FBRANCH2 $DEFAULTBRANCH); do
    echo "Attempting downloads from: $BRANCH"
    if [[ $USEREPO == "d" ]]; then
        BRANCH_URL=${BRANCH_URL:="jobs/artifacts/$BRANCH/raw/release"}
        # Get URLs for artifacts from all relevant repos
        UDB_URL=${UDB_URL:="${REPOS_API}user-discovery-bot/$BRANCH_URL/udb$BIN"}
        SERVER_URL=${SERVER_URL:="${REPOS_API}server/$BRANCH_URL/server$BIN"}
        GW_URL=${GW_URL:="${REPOS_API}gateway/$BRANCH_URL/gateway$BIN"}
        PERMISSIONING_URL=${PERMISSIONING_URL:="${REPOS_API}registration/$BRANCH_URL/registration$BIN"}
        CLIENT_URL=${CLIENT_URL:="${REPOS_API}client/$BRANCH_URL/client$BIN"}
        SERVER_GPU_URL=${SERVER_GPU_URL:="${REPOS_API}server/$BRANCH_URL/server-cuda.linux64?job=build"}
        GPULIB_URL=${GPULIB_URL:="${REPOS_API}server/$BRANCH_URL/libpowmosm75.so?job=build"}
        GPULIB2_URL=${GPULIB2_URL:="${REPOS_API}server/$BRANCH_URL/libpow.fatbin?job=build"}
        CLIENT_REG_URL=${CLIENT_REG_URL:="${REPOS_API}client-registrar/$BRANCH_URL/registration$BIN"}
    else
        UDB_URL=${UDB_URL:="${REPOS_API}/$BRANCH/udb$BIN"}
        SERVER_URL=${SERVER_URL:="${REPOS_API}/$BRANCH/server$BIN"}
        GW_URL=${GW_URL:="${REPOS_API}/$BRANCH/gateway$BIN"}
        PERMISSIONING_URL=${PERMISSIONING_URL:="${REPOS_API}/$BRANCH/registration.stateless$BIN"}
        CLIENT_URL=${CLIENT_URL:="${REPOS_API}/$BRANCH/client$BIN"}
        CLIENT_REG_URL=${CLIENT_REG_URL:="${REPOS_API}client-registrar/$BRANCH_URL/registration$BIN"}
    fi

    set -x

    # Silently download the UDB binary to the provisioning directory
    if [ ! -f $download_path/udb ] && [[ "$UDB_URL" != *"forcedbranch"* ]]; then
        curl -s -f -L -H "PRIVATE-TOKEN: $GITLAB_ACCESS_TOKEN" -o "$download_path/udb" ${UDB_URL}
    fi

    # Silently download the Server binary to the provisioning directory
    if [ ! -f $download_path/server ] && [[ "$SERVER_URL" != *"forcedbranch"* ]]; then
        curl -s -f -L -H "PRIVATE-TOKEN: $GITLAB_ACCESS_TOKEN" -o "$download_path/server" ${SERVER_URL}
    fi

    # Silently download the Gateway binary to the provisioning directory
    if [ ! -f $download_path/gateway ] && [[ "$GW_URL" != *"forcedbranch"* ]]; then
        curl -s -f -L -H "PRIVATE-TOKEN: $GITLAB_ACCESS_TOKEN" -o "$download_path/gateway" ${GW_URL}
    fi

    # Silently download the permissioning binary to the provisioning directory
    if [ ! -f $download_path/permissioning ] && [[ "$PERMISSIONING_URL" != *"forcedbranch"* ]]; then
        curl -s -f -L -H "PRIVATE-TOKEN: $GITLAB_ACCESS_TOKEN" -o "$download_path/permissioning" ${PERMISSIONING_URL}
    fi

    # Silently download the permissioning binary to the provisioning directory
    if [ ! -f $download_path/client ] && [[ "$CLIENT_URL" != *"forcedbranch"* ]]; then
        curl -s -f -L -H "PRIVATE-TOKEN: $GITLAB_ACCESS_TOKEN" -o "$download_path/client" ${CLIENT_URL}
    fi

        # Silently download the client registrar binary to the provisioning directory
    if [ ! -f $download_path/client-registrar ] && [[ "$CLIENT_REG_URL" != *"forcedbranch"* ]]; then
        curl -s -f -L -H "PRIVATE-TOKEN: $GITLAB_ACCESS_TOKEN" -o "$download_path/client-registrar" ${CLIENT_REG_URL}
    fi

if [[ $2 == "d" ]]; then
    # Silently download the Server binary to the provisioning directory
    if [ ! -f $download_path/server-cuda ] && [[ "$SERVER_GPU_URL" != *"forcedbranch"* ]]; then
        curl -s -f -L -H "PRIVATE-TOKEN: $GITLAB_ACCESS_TOKEN" -o "$download_path/server-cuda" ${SERVER_GPU_URL}
    fi

    # Silently download the GPU Library to the provisioning directory
    if [ ! -f $download_path/libpowmosm75.so ] && [[ "$GPULIB_URL" != *"forcedbranch"* ]]; then
        curl -s -f -L -H "PRIVATE-TOKEN: $GITLAB_ACCESS_TOKEN" -o "$download_path/libpowmosm75.so" ${GPULIB_URL}
    fi
    # Silently download the GPU Library to the provisioning directory
    if [ ! -f $download_path/libpow.fatbin ] && [[ "$GPULIB2_URL" != *"forcedbranch"* ]]; then
        curl -s -f -L -H "PRIVATE-TOKEN: $GITLAB_ACCESS_TOKEN" -o "$download_path/libpow.fatbin" ${GPULIB2_URL}
    fi

        # Silently download the client registrar binary to the provisioning directory
    if [ ! -f $download_path/client-registrar ] && [[ "$CLIENT_REG_URL" != *"forcedbranch"* ]]; then
        curl -s -f -L -H "PRIVATE-TOKEN: $GITLAB_ACCESS_TOKEN" -o "$download_path/client-registrar" ${CLIENT_REG_URL}
    fi
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
    unset GPULIB2_URL
    unset CLIENT_REG_URL
done

# Make binaries executable
chmod +x "$download_path"/[^l]*

file "$download_path"/*

echo "If you see HTML or anything but linux/mac binaries above, something is messed up!"
