#!/usr/bin/env python3
from __future__ import annotations

import os
import string
import random
import argparse
from collections.abc import Sequence
# Generates a random string
def random_string(stringLength=4):
    letters = string.ascii_lowercase
    return ''.join(random.choice(letters) for i in range(stringLength))


# Generate a list of all ports servers and gateways occupy. Doing this as a
# separate step because their configs need every one listed, and generating them
# once is lighter on CPU cycles. Takes an offset to ensure no port collisions
# occur with existing packages
def create_ports_list(offset, manualOffset=0):
    # Array of integers for ports of each server and gateway in the network
    gateway_ports = []
    node_ports = []
    node_regCodes = []

    for i in range(nodes):
        gateway_ports.append(1000 + 1000 * offset + manualOffset + i)
        node_ports.append(10000 + 1000 * offset + i)

        regCode = random_string()
        # If this regCode is already in the list, we loop until we get one that
        # isn't
        while regCode in node_regCodes:
            regCode = random_string()
        node_regCodes.append(regCode)
    return gateway_ports, node_ports, node_regCodes

# Generate server and gateway configs
def generate_server_side_config(offset, newPackage):

    nodes = 5

    server_template = ""
    with open("gen/server.yaml") as f:
        server_template = f.read()

    gateway_template = ""
    with open("gen/gateway.yaml") as f:
        gateway_template = f.read()

    reg_template = ""
    with open("gen/permissioning.yaml") as f:
        reg_template = f.read()

    reg_json_template = ""
    with open("gen/registration.json") as f:
        reg_json_template = f.read()



    gateway_ports, node_ports, node_regCodes = create_ports_list(offset)



    for i in range(nodes):
        with open(newPackage + "/configurations/servers/server-{}.yml".format(i), 'w') as f:
            # Array of strings defining node and gateway IPs and ports
            node_addrs = []
            node_addrs.append("\"{}\"".format(node_ports[i]))

            # Create a new config based on template
            s_config = server_template.replace("server-1", "server-" + str(i)) \
                .replace("gateway-1", "gateway-" + str(i)) \
                .replace("{NODE_ADDR}", "\r\n".join(node_addrs)) \
                .replace("{DB_ADDR}", "".join(["\"\""])) \
                .replace("AAAA", node_regCodes[i]) \
                .replace("nodeID-1.json", "nodeID-"+str(i)+".json") \
                .replace("errServer-0.txt", "errServer-"+str(i)+".txt")
            f.write(s_config)


        with open(newPackage + "/configurations/gateways/gateway-{}.yml".format(i), 'w') as f:
            # Array of strings defining node and gateway IPs and ports
            node_addrs = []
            node_addrs.append(" \"0.0.0.0:{}\"".format(node_ports[i]))

            # Create a new config based on template
            g_config = gateway_template.replace("server-1", "server-" + str(i)) \
                .replace("gateway-1", "gateway-" + str(i)) \
                .replace("8200", str(gateway_ports[i])) \
                .replace("{NODE_ADDR}", "\r\n".join(node_addrs)) \
                .replace("gatewayIDF-0", "gatewayIDF-" + str(i))

            f.write(g_config)



    # Generate regCodes file
    with open(newPackage + "/configurations/regCodes.json", "w") as f:
        f.write("[")

        for i in range(nodes):
            f.write("{\"RegCode\": \"" + node_regCodes[i] + "\", \"Order\": \"" + \
                str(i) + "\"}")
            # If not the last element, write a comma
            if i is not (nodes - 1):
                f.write(",")

        f.write("]")


# Count the number of packages previously created by counting
# run.sh files creates
def count_run_sh_files():
    current_dir = os.getcwd()
    count = 0
    for root, dirs, files in os.walk(current_dir):
        for file in files:
            if file == "run.sh":
                count += 1
    return count


def main(argv: Sequence[str] | None = None) -> int:
    run_sh_count = count_run_sh_files()

    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Add sub-commands
    count_parser = subparsers.add_parser("count", help="This will count the number of run.sh and print the result.")
    count_parser.add_argument("string")


    gen_parser = subparsers.add_parser("generate", description="Generates a template package that can be used for client tests.")
    gen_parser.add_argument("offset", type=int, default=0, help="Optional argument. Used when several programmers are separating tests simultaneously.")
    gen_parser.add_argument("pkg", help="The name of the package that will be generated.")

    args = parser.parse_args(argv)

    if args.command == "count":
        print(f"Number of occurrences of run.sh in all subdirectories: {run_sh_count}")
        return
    elif args.command == "generate":
        # todo: It may be that the serveral programmers are separating tests
        # simultaneously. If they are doing this, it's likely their offsets will be
        # the same and they will generate newtorks operating on the same port.
        # In which case, there should be some way to input
        # an argument to just run the count function and output the result.
        # Instruct in the guide (some readme) that the user should post this offset
        # Have an argument that  takes this offset and adds it to run_sh_count
        # Request new package name from user
        #newPackage = string(input("Name of new package: "))
        #os.makedirs(os.path.dirname(newPackage), exist_ok=True)
        generate_server_side_config(run_sh_count + args.offset, args.pkg)
    else:
        raise NotImplementedError(
            f"Command {args.command} does not exist.",
        )



if __name__ == "__main__":
    raise SystemExit(main())
