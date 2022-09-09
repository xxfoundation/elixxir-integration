#!/bin/bash

# If we are on a feature branch, add it to the eval list
FBRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CI_BUILD_REF_NAME" != "" ]]; then
    FBRANCH=$CI_BUILD_REF_NAME
fi
FBRANCH=$(echo $FBRANCH | grep feature)
# Also check for the branch name without the "feature" on it.
FBRANCH2=$(echo $FBRANCH | sed 's/feature\///g')

LOCALPATH=$(pwd)
BINARYPATH=$LOCALPATH/bin

# Clean up pathing
rm -rf gitlab.com/*
rm -rf bin/*
mkdir -p bin
mkdir -p bin

CHECKOUTBRANCH=""
setCheckoutBranch() {
  CHECKOUTBRANCH="release"
  if [[ -z "$FBRANCH" ]]; then
    CHECKOUTBRANCH=$FBRANCH
  fi
  if [[ -z "$FBRANCH2" ]]; then
    CHECKOUTBRANCH=$FBRANCH2
  fi

}

pushd bin

# Download client
git clone https://git.xx.network/elixxir/client gitlab.com/elixxir/client
pushd gitlab.com/elixxir/client
setCheckoutBranch
git checkout $CHECKOUTBRANCH
go mod vendor -v
go mod tidy
go build -mod vendor -o "$BINARYPATH/client" main.go
popd

# Download UD
echo "Downloading user discovery..."
git clone https://git.xx.network/elixxir/user-discovery-bot gitlab.com/elixxir/user-discovery-bot
pushd gitlab.com/elixxir/user-discovery-bot
setCheckoutBranch
git checkout $CHECKOUTBRANCH
go mod vendor -v
go mod tidy
go build -mod vendor -o "$BINARYPATH/udb" main.go
popd

# Download scheduling server
echo "Downloading scheduling server..."
git clone https://git.xx.network/elixxir/registration gitlab.com/elixxir/registration
pushd gitlab.com/elixxir/registration
setCheckoutBranch
git checkout $CHECKOUTBRANCH
go mod vendor -v
go mod tidy
go build -mod vendor -o "$BINARYPATH/permissioning" main.go
popd

# Download client registrar
echo "Downloading client registrar"
git clone https://git.xx.network/elixxir/client-registrar.git gitlab.com/elixxir/client-registrar
pushd gitlab.com/elixxir/client-registrar
setCheckoutBranch
git checkout $CHECKOUTBRANCH
go mod vendor -v
go mod tidy
go build -mod vendor -o "$BINARYPATH/client-registrar" gitlab.com/elixxir/client-registrar
popd

# Download cMix node
echo "Downloading cMix node..."
git clone https://git.xx.network/elixxir/server gitlab.com/elixxir/server
pushd gitlab.com/elixxir/server
setCheckoutBranch
git checkout $CHECKOUTBRANCH
go mod vendor -v
go mod tidy
go build -mod vendor -o "$BINARYPATH/server main".go
popd

# Download cMix gateway
echo "Downloading cMix gateway..."
git clone https://git.xx.network/elixxir/gateway gitlab.com/elixxir/gateway
pushd gitlab.com/elixxir/gateway
setCheckoutBranch
git checkout $CHECKOUTBRANCH
go mod vendor -v
go mod tidy
make clean
go build -mod vendor -o "$BINARYPATH/gateway" main.go
popd


popd
