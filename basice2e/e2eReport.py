#!/usr/bin/env python3

# This script is used for building reports on dropped E2E integration tests
import logging

import re
import glob
import os
import logging as log

resultsDir = "./results/clients"


def err(s):
    """
    Helper for printing errors and exiting

    :param s: Error string to print
    """
    log.error(s)
    exit(1)


def find_files():
    """Obtains list of files to search."""
    if not os.path.isdir(resultsDir):
        err("Directory {} does not exist!".format(resultsDir))
    return glob.glob('{}/client*.log'.format(resultsDir))


def read_file(path, phrases):
    """Reads the lines of a file."""
    while 1:
        with open(path, 'r') as file:
            line = file.readline()
            if not line:
                break
            else:
                for phrase in phrases:
                    if phrase in line:
                        yield line


def main():
    log.basicConfig(format='[%(levelname)s] %(asctime)s: %(message)s',
                    level=log.INFO, datefmt='%d-%b-%y %H:%M:%S')
    log_files = find_files()

    messages_sent = dict()
    messages_received = dict()
    rounds_sent = dict()

    # Scan each log file
    for path in log_files:
        log.info("Scanning {}".format(path))
        with open(path, 'r') as file:
            while True:
                line = file.readline()
                if not line:
                    break
                else:
                    if "Successfully sent to EphID" in line:
                        # Capture message sending
                        sent_message = re.findall('msgDigest: (.{20})\)', line)[0]
                        log.debug("Located sent message: {}".format(sent_message))
                        messages_sent[sent_message] = {"sender": os.path.basename(path)}

                        # Capture rounds messages were sent in
                        sent_round = re.findall('\) in round ([0-9]+)', line)[0]
                        log.debug("Located sent round: {}".format(sent_round))
                        messages_sent[sent_message]["round"] = sent_round
                        if sent_round not in rounds_sent:
                            rounds_sent[sent_round] = False

                    elif "Received message of type" in line:
                        # Capture message receiving
                        received_messages = re.findall(' msgDigest: (.{20})', line)
                        for received_message in received_messages:
                            log.debug("Located received message: {}".format(received_message))
                            messages_received[received_message] = os.path.basename(path)

                    elif "Round(s)" in line:
                        # Capture round success
                        successful_rounds = re.findall('Round\(s\) ([0-9]+) successful', line)
                        for successful_round in successful_rounds:
                            log.debug("Located successful round: {}".format(successful_round))
                            rounds_sent[successful_round] = True

    # Print results
    num_successful = 0
    for msgDigest, senderDict in messages_sent.items():
        if msgDigest in messages_received:
            log.debug("Message {} sent by {} on round {} was received".format(msgDigest,
                                                                              senderDict["sender"],
                                                                              senderDict["round"]))
            num_successful += 1
        else:
            log.error("Message {} sent by {} on round {} was NOT received".format(msgDigest,
                                                                                  senderDict["sender"],
                                                                                  senderDict["round"]))
    for round_id, was_successful in rounds_sent.items():
        if was_successful:
            log.debug("Round {} was successful".format(round_id))
        else:
            log.warning("Round {} was NOT confirmed successful, messages may have been dropped".format(round_id))

    log.info("{}/{} messages received successfully!".format(num_successful, len(messages_sent)))


if __name__ == "__main__":
    main()

# INFO 2021/05/07 15:25:14 Received message of type None from ouQD89J4YdmlzcAkdjjgVa49SANsi1JL5JLVjrWjZtED, msgDigest: inDu2/zmGD+vtCMVHXdg
# INFO 2021/05/19 15:29:09 Received 2 messages in Round 65253 for -7 (AAAAAAAAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD)
# INFO 2021/05/07 15:25:03 Sending to EphID -15 (ouQD89J4YdmlzcAkdjjgVa49SANsi1JL5JLVjrWjZtED) on round 797, (msgDigest: YTuZd9p8759GBMNz8Dw7, ecrMsgDigest: JshXEJ4WTBsbRFWQDBYq) via gateway sAtfNaRd1jePhfRrcDgZgHHAAmhZ/F0jDbD4JgAfkMsB
# INFO 2021/05/07 15:25:04 Successfully sent to EphID -15 (source: ouQD89J4YdmlzcAkdjjgVa49SANsi1JL5JLVjrWjZtED) in round 797 (msgDigest: YTuZd9p8759GBMNz8Dw7)
# INFO 2021/05/07 15:25:04 Result of sending message "Hello from Rick42, with E2E Encryption" to "ouQD89J4YdmlzcAkdjjgVa49SANsi1JL5JLVjrWjZtED":
# INFO 2021/05/07 15:25:04 	Round(s) 795 successful