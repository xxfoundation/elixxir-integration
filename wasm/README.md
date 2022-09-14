# Running WASM Tests

To run WASM tests, servers and gateways are run like normal, but the client is
served by an HTTP server in the browser.

The `testServer` directory contains a basic HTTP server (`clientServer.go`) and
various directories each containing a different example. Each example contains
one or more cMix clients running in javascript. The `assets` directory contains
files used by all the examples.

To run the server, first ensure the compiled bindings are in the `bin`
directory. Then run the server

```shell
$ GOOS=js GOARCH=wasm go build -o examples/xxdk.wasm
$ cd testServer/
$ go run clientServer.go
```

Navigate to http://localhost:9090 to see a list of files in the server and
navigate to a `.html` file in any of the examples to open a client.

To start the network, run `run.sh` in the console.


## `wasm_exec.js`

`wasm_exec.js` is provided by Go and is used to import the WebAssembly module in
the browser. It can be retrieved from Go using the following command.

```shell
$ cp "$(go env GOROOT)/misc/wasm/wasm_exec.js" test/assets/
```

Note that this repository makes edits to `wasm_exec.js` and you must either use
the one in this repository or add the following lines in the `go` `importObject`
on `global.Go`.

```javascript
global.Go = class {
    constructor() {
        // ...
        this.importObject = {
            go: {
                // ...
                // func Throw(exception string, message string)
                'gitlab.com/elixxir/xxdk-wasm/utils.throw': (sp) => {
                    const exception = loadString(sp + 8)
                    const message = loadString(sp + 24)
                    throw globalThis[exception](message)
                },
            }
        }
    }
}
```
