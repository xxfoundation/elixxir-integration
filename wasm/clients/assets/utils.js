////////////////////////////////////////////////////////////////////////////////
// Copyright © 2022 xx foundation                                             //
//                                                                            //
// Use of this source code is governed by a license that can be found in the  //
// LICENSE file.                                                              //
////////////////////////////////////////////////////////////////////////////////

// Function to download data to a file.
function download(filename, data) {
    const file = new Blob([data], {type: 'text/plain'});
    let a = document.createElement("a"),
        url = URL.createObjectURL(file);
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    setTimeout(function() {
        document.body.removeChild(a);
        window.URL.revokeObjectURL(url);
    }, 0);
}

// sleepUntil waits until the condition f is met or until the timeout is
// reached.
async function sleepUntil(f, timeoutMs) {
    return new Promise((resolve, reject) => {
        const timeWas = new Date();
        const wait = setInterval(function() {
            if (f()) {
                console.log("resolved after", new Date() - timeWas, "ms");
                clearInterval(wait);
                resolve();
            } else if (new Date() - timeWas > timeoutMs) { // Timeout
                console.log("rejected after", new Date() - timeWas, "ms");
                clearInterval(wait);
                reject();
            }
        }, 20);
    });
}

// newHtmlConsole returns an object that allows for printing log messages or
// error messages to an element.
function newHtmlConsole(elem) {
    return {
        log: function (message) {
            console.log(message)
            elem.innerHTML += "<p>" + message + "</p>"
        },
        error: function (message) {
            console.error(message)
            elem.innerHTML += "<p class='error'>" + message + "</p>"
        }
    };
}