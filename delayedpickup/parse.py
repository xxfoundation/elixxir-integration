#!/usr/bin/env python3

from datetime import datetime

pwd = "/Users/jonahhusson/gitlab.com/elixxir/integration/delayedpickup"


def main():
    # SENDER LOGS
    client42_log = get_file_contents(pwd+"/results/clients/client42-wv.log")
    client42_text = get_file_contents(pwd+"/results/clients/client42-wv.txt")

    # RECEIVER LOGS
    client43_log = get_file_contents(pwd+"/results/clients/client43-wv.log")
    client43_text = get_file_contents(pwd+"/results/clients/client43-wv.txt")

    messages = {}
    failedrounds = {}
    sendcnt = 0
    for ind, l in enumerate(client42_log):
        try:
            temp = l.split(' ', 3)
            level = temp[0]
            date = temp[1]
            time = temp[2]
            rest = temp[3]
            if level == "INFO" and "Successfully sent to EphID" in rest:
                digest = rest[rest.rfind("(")+1:rest.rfind(")")].split(" ")[1]
                source = rest[rest.find("(")+1:rest.find(")")].split(" ")[1]
                to_round = rest[rest.find("round"):].split()[1]
                if not to_round.isnumeric():
                    print(f"WARNING: Parsed round id {to_round} is not numeric")
                    to_round = -1
                messages[digest] = {"sent": (date, time), "receiverID": source, "sentRound": int(to_round)}
                sendcnt += 1
            elif "Result of sending message" in rest:
                statusmsgs = [l for l in client42_log[ind+1:ind+3] if "Round" in l and ("failed" in l or "timed" in l)]
                for msg in statusmsgs:
                    for part in msg.split():
                        if part.isnumeric():
                            failedrounds[int(part)] = True
        except Exception as e:
            pass

    recvcnt = 0
    for ind, l in enumerate(client43_log):
        try:
            temp = l.split(' ', 3)
            level = temp[0]
            date = temp[1]
            time = temp[2]
            rest = temp[3]
            if level == "INFO" and "Received message of type E2E" in rest:
                digest = rest.split(" ")[-1].strip()
                sender_id = rest[rest.find("from"):].split()[1]
                messages[digest]['received'] = (date, time)
                messages[digest]['senderID'] = sender_id
                recvcnt += 1
        except Exception as e:
            pass

    for key, val in messages.items():
        round = val['sentRound']
        if round in failedrounds.keys():
            del messages[key]
        sent = val['sent']
        sent_parsed = datetime.strptime(sent[0] + " " + sent[1], "%Y/%m/%d %H:%M:%S.%f")
        received = val['received']
        received_parsed = datetime.strptime(received[0] + " " + received[1], "%Y/%m/%d %H:%M:%S.%f")
        print(f"Message [{key}]: sent {sent_parsed}, received {received_parsed}, delta: {received_parsed - sent_parsed}")


def get_file_contents(path):
    with open(path, "r") as f:
        return f.readlines()


if __name__ == "__main__":
    main()
