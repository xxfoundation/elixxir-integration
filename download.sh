#!/bin/bash
LOCALPATH=$(pwd)
mkdir -p bin
git clone https://git.xx.network/elixxir/client gitlab.com/elixxir/client
pushd gitlab.com/elixxir/client
go mod vendor -v
go mod tidy
go build -mod vendor -o $LOCALPATH/bin/client main.go
popd
echo "Downloading user discovery..."
git clone https://git.xx.network/elixxir/user-discovery-bot gitlab.com/elixxir/user-discovery-bot
pushd gitlab.com/elixxir/user-discovery-bot
go mod vendor -v
go mod tidy
go build -mod vendor -o $LOCALPATH/bin/udb main.go
popd
echo "Downloading permissioning server..."
git clone https://git.xx.network/elixxir/registration gitlab.com/elixxir/registration
pushd gitlab.com/elixxir/registration
go mod vendor -v
go mod tidy
go build -mod vendor -o $LOCALPATH/bin/permissioning main.go
popd
echo "Downloading client registrar"
git clone https://git.xx.network/elixxir/client-registrar.git gitlab.com/elixxir/client-registrar
pushd gitlab.com/elixxir/client-registrar
go mod vendor -v
go mod tidy
go build -mod vendor -o $LOCALPATH/bin/client-registrar gitlab.com/elixxir/client-registrar
popd
echo "Downloading cMix node..."
git clone https://git.xx.network/elixxir/server gitlab.com/elixxir/server
pushd gitlab.com/elixxir/server
go mod vendor -v
go mod tidy
go build -mod vendor -o $LOCALPATH/bin/server main.go
popd
echo "Downloading cMix gateway..."
git clone https://git.xx.network/elixxir/gateway gitlab.com/elixxir/gateway
pushd gitlab.com/elixxir/gateway
go mod vendor -v
go mod tidy
make clean
go build -mod vendor -o $LOCALPATH/bin/gateway main.go
popd
