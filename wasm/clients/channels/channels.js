////////////////////////////////////////////////////////////////////////////////
// Copyright © 2022 xx foundation                                             //
//                                                                            //
// Use of this source code is governed by a license that can be found in the  //
// LICENSE file.                                                              //
////////////////////////////////////////////////////////////////////////////////



async function Channels(htmlConsole, messageConsole, stopNetworkFollowerBtn, ndf,
                        statePath, statePassString) {

    document.getElementById("startCmix").style.display = "none";

    const statePass = enc.encode(statePassString);

    console.log("Starting client with:" +
        "\n\tstatePath: " + statePath +
        "\n\tstatePass: " + statePassString)
    htmlConsole.log("Starting client with path " + statePath)

    // Check if state exists
    if (localStorage.getItem(statePath) === null) {

        htmlConsole.log("No state found at " + statePath + ". Calling NewCmix.")

        // Initialize the state
        NewCmix(ndf, statePath, statePass, '');
    } else {
        htmlConsole.log("State found at " + statePath)
    }


    ////////////////////////////////////////////////////////////////////////////
    // Login to your client session                                           //
    ////////////////////////////////////////////////////////////////////////////

    // Login with the same statePath and statePass used to call NewCmix
    htmlConsole.log("Starting to load cmix with path " + statePath)
    let net;
    try {
        net = await LoadCmix(statePath, statePass, GetDefaultCMixParams());
    } catch (e) {
        htmlConsole.error("Failed to load Cmix: " + e)
        return
    }
    htmlConsole.log("Loaded Cmix.")
    console.log("Loaded Cmix: " + JSON.stringify(net))

    // Get reception identity (automatically created if one does not exist)
    const identityStorageKey = "identityStorageKey";
    let identity;
    try {
        htmlConsole.log("Getting reception identity.")
        identity = LoadReceptionIdentity(identityStorageKey, net.GetID());
    } catch (e) {
        htmlConsole.log("No reception identity found. Generating a new one.")

        // If no extant xxdk.ReceptionIdentity, generate and store a new one
        identity = await net.MakeReceptionIdentity();

        StoreReceptionIdentity(identityStorageKey, identity, net.GetID());
    }

    let authCallbacks = {
        Confirm: function (contact, receptionId, ephemeralId, roundId) {
            htmlConsole.log("Confirm: from " + Uint8ArrayToBase64(receptionId) + " on round " + roundId)
        },
        Request: async function (contact, receptionId, ephemeralId, roundId) {
            htmlConsole.log("Request: from " + Uint8ArrayToBase64(receptionId) + " on round " + roundId)
        },
        Reset: function (contact, receptionId, ephemeralId, roundId) {
            htmlConsole.log("Reset: from " + Uint8ArrayToBase64(receptionId) + " on round " + roundId)
        }
    }


    // Create an E2E client
    // Pass in auth object which controls auth callbacks for this client
    htmlConsole.log("Logging in E2E")
    let e2eClient = Login(net.GetID(), authCallbacks, identity, new Uint8Array(null));
    htmlConsole.log("Logged in E2E")

    ////////////////////////////////////////////////////////////////////////////
    // Start network threads                                                  //
    ////////////////////////////////////////////////////////////////////////////

    // Set networkFollowerTimeout to a value of your choice (seconds)
    net.StartNetworkFollower(5000);

    htmlConsole.log("Started network follower")

    stopNetworkFollowerBtn.style.display = 'block';
    stopNetworkFollowerBtn.addEventListener('click', async () => {
        htmlConsole.log("Stopping network follower")
        try {
            await net.StopNetworkFollower()
        } catch (e) {
            htmlConsole.log("Failed to stop network follower: " + e)
        }
    })

    // Wait for network to become healthy
    htmlConsole.log("Waiting for network to be healthy")
    await net.WaitForNetwork(25000).then(
        () => {
            htmlConsole.log("Network is healthy")
        },
        () => {
            htmlConsole.error("Timed out. Network is not healthy.")
            throw new Error("Timed out. Network is not healthy.")
        }
    )

    let chanNameInput = document.getElementById("chanName")
    let chanDescriptionInput = document.getElementById("chanDescription")
    let makeChannelSubmit = document.getElementById("makeChannelSubmit")
    let prettyPrintInput = document.getElementById("prettyPrintInput")
    let joinChannelSubmit = document.getElementById("joinChannelSubmit")
    let usernameInput1 = document.getElementById("username1")
    let usernameInput2 = document.getElementById("username2")

    let chanNameOutput = document.getElementById("chanNameOutput")
    let chanDescriptionOutput = document.getElementById("chanDescriptionOutput")
    let chanIdOutput = document.getElementById("chanIdOutput")
    let prettyPrintOutput = document.getElementById("prettyPrintOutput")

    chanNameInput.disabled = false
    chanDescriptionInput.disabled = false
    makeChannelSubmit.disabled = false
    prettyPrintInput.disabled = false
    joinChannelSubmit.disabled = false
    usernameInput1.disabled = false
    usernameInput2.disabled = false


    makeChannelSubmit.addEventListener("click", () => {
        const chanName = chanNameInput.value
        const chanDescription = chanDescriptionInput.value

        let chanGen = JSON.parse(dec.decode(GenerateChannel(net.GetID(), chanName, chanDescription)))


        const username = usernameInput1.value

        joinChannel(htmlConsole, messageConsole, e2eClient, username,
            chanGen.Channel, chanNameOutput, chanDescriptionOutput,
            chanIdOutput, prettyPrintOutput)
    })



    joinChannelSubmit.addEventListener("click", () => {
        const username = usernameInput2.value
        joinChannel(htmlConsole, messageConsole, e2eClient, username,
            prettyPrintInput.value, chanNameOutput, chanDescriptionOutput,
            chanIdOutput, prettyPrintOutput)
    })


}

async function joinChannel(htmlConsole, messageConsole, e2eClient, username,
                           prettyPrint, nameOutput, descriptionOutput, idOutput,
                           prettyPrintOutput) {
   document.getElementById("makeChannel").style.display = "none";
   document.getElementById("joinChannel").style.display = "none";

    let eventModel = {
        JoinChannel: function (channel){},
        LeaveChannel: function (channelID){},
        ReceiveMessage: function (channelID, messageID, senderUsername, text, timestamp, lease, roundId, status){
            messageConsole.log(senderUsername + " said: " + text)
            htmlConsole.log(senderUsername + ": " + text)
        },
        ReceiveReply: function (channelID, messageID, reactionTo, senderUsername, text, timestamp, lease, roundId, status){},
        ReceiveReaction: function (channelID, messageID, reactionTo, senderUsername, reaction, timestamp, lease, roundId, status){},
        UpdateSentStatus: function (messageID, status){},
    }

    let chanManager = NewChannelsManagerDummyNameService(e2eClient.GetID(), username, eventModel)

    let chanInfo = JSON.parse(dec.decode(chanManager.JoinChannel(prettyPrint)))

    nameOutput.value = chanInfo.Name
    descriptionOutput.value = chanInfo.Description
    idOutput.value = chanInfo.ChannelID
    prettyPrintOutput.value = prettyPrint


    let sendMessageSubmit = document.getElementById("sendMessageSubmit")
    let messageInput = document.getElementById("message")
    sendMessageSubmit.disabled = false
    messageInput.disabled = false
    sendMessageSubmit.addEventListener("click", async () => {
        let message = messageInput.value
        messageInput.value = ""
        let chanSendReportJson = await chanManager.SendMessage(
            Base64ToUint8Array(chanInfo.ChannelID), message, 30000, new Uint8Array(null))
        htmlConsole.log("chanSendReport: " + dec.decode(chanSendReportJson))
    })
}