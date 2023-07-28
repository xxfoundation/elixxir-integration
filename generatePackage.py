#!/usr/bin/env python3
from __future__ import annotations

import os
import string
import random
import argparse
import re
from collections.abc import Sequence
# Generates a random string
def random_string(stringLength=4):
    letters = string.ascii_lowercase
    return ''.join(random.choice(letters) for i in range(stringLength))

nodes = 5


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
        gateway_ports.append(1000 + 10 * offset + manualOffset + i)
        node_ports.append(10000 + 10 * offset + i)

        regCode = random_string()
        # If this regCode is already in the list, we loop until we get one that
        # isn't
        while regCode in node_regCodes:
            regCode = random_string()
        node_regCodes.append(regCode)

    permissioningPort = 20000 + 10 * offset

    udbPort = 30000 + 10 * offset



    return gateway_ports, node_ports, permissioningPort, udbPort, node_regCodes

# Generate server and gateway configs
def generate_server_side_config(offset: int, newPackage: string):

    # Open gateway template
    gateway_template = ""
    with open("gen/gateway.yaml") as f:
        gateway_template = f.read()

    # Open network config
    network_config = ""
    with open("gen/network.config") as f:
        network_config = f.read()

    # Open no errors template
    no_errors = ""
    with open("gen/noerrors.txt") as f:
        no_errors = f.read()

    # Open whitelist template
    whitelist = ""
    with open("gen/whitelist.txt") as f:
        whitelist = f.read()

    # Open release template
    release_template = ""
    with open("gen/release.txt") as f:
        release_template = f.read()

    # Open mainnet template
    mainnet_template = ""
    with open("gen/mainnet.txt") as f:
        mainnet_template = f.read()

    # Open devnet template
    devnet_template = ""
    with open("gen/devnet.txt") as f:
        devnet_template = f.read()

    #Open betanet template
    betanet_template = ""
    with open("gen/betanet.txt") as f:
        betanet_template = f.read()

    # Open permissioning template
    reg_template = ""
    with open("gen/permissioning.yaml") as f:
        reg_template = f.read()

    # Open client-registrar
    client_reg_template = ""
    with open("gen/client-registrar.yaml") as f:
        client_reg_template = f.read()

    # Open server template
    server_template = ""
    with open("gen/server.yaml") as f:
        server_template = f.read()


    # Open run script template
    run_template=""
    with open("gen/run.sh") as f:
        run_template = f.read()

    # Open udb config
    udb_config = ""
    with open("gen/udb.yaml") as f:
        udb_config = f.read()

    # Open udb contact
    udb_contact = ""
    with open("gen/udbContact.bin") as f:
        udb_contact = f.read()

    reg_json = ""
    with open("gen/registration.json") as f:
        reg_json = f.read()

    # Open udb proto file
    udb_proto = ""
    with open("gen/udbProto.json") as f:
        udb_proto = f.read()

    # Create package
    if not os.path.exists(newPackage):
        os.makedirs(newPackage)

    # Create gold sub-directory
    if not os.path.exists("{}/clients.goldoutput/".format(newPackage)):
        os.makedirs("{}/clients.goldoutput/".format(newPackage))


    gateway_ports, node_ports, perm_port, udbPort, node_regCodes = create_ports_list(offset)

    for i in range(nodes):
        with open("{}/server-{}.yaml".format(newPackage, i+1), 'w') as f:
            # Array of strings defining node and gateway IPs and ports
            node_addrs = []
            node_addrs.append("\"{}\"".format(node_ports[i]))

            # Create a new config based on template
            s_config = server_template.replace("server-1", "server-" + str(i+1)) \
                .replace("gateway-1", "gateway-" + str(i)) \
                .replace("{NODE_ADDR}", "\r\n".join(node_addrs)) \
                .replace("{DB_ADDR}", "".join(["\"\""])) \
                .replace("AAAA", node_regCodes[i]) \
                .replace("nodeID-1.json", "nodeID-"+str(i)+".json") \
                .replace("errServer-0.txt", "errServer-"+str(i)+".txt") \
                .replace("{permissioning_port}", str(perm_port))
            f.write(s_config)


        with open("{}/gateway-{}.yaml".format(newPackage, i+1), 'w') as f:
            # Array of strings defining node and gateway IPs and ports
            node_addrs = []
            node_addrs.append(" \"0.0.0.0:{}\"".format(node_ports[i]))

            # Create a new config based on template
            g_config = gateway_template.replace("server-1", "server-" + str(i+1)) \
                .replace("gateway-1", "gateway-" + str(i+1)) \
                .replace("{GW_ADDR}", str(gateway_ports[i])) \
                .replace("{NODE_ADDR}", "\r\n".join(node_addrs)) \
                .replace("gatewayIDF-0", "gatewayIDF-" + str(i))

            f.write(g_config)



    # Generate regCodes file
    with open("{}/regCodes.json".format(newPackage), "w") as f:
        f.write("[")

        for i in range(nodes):
            f.write("{\"RegCode\": \"" + node_regCodes[i] + "\", \"Order\": \"" + \
                "CR" + "\"}")
            # If not the last element, write a comma
            if i is not (nodes - 1):
                f.write(",")

        f.write("]")


    # Generate network config
    with open("{}/network.config".format(newPackage), "w") as f:
        network_config = network_config.replace("{entry_point}", str(gateway_ports[0]))
        f.write(network_config)

    # Generate permissioning config
    with open("{}/permissioning.yaml".format(newPackage), "w") as f:
        reg_template = reg_template.replace("{permissioning_port}", str(perm_port))  \
            .replace("{udb_port}", str(udbPort))\
            .replace("{registration_port}", str(perm_port+1))
        f.write(reg_template)

   # Generate registration configs
    with open("{}/registration.json".format(newPackage), "w") as f:
        f.write(reg_json)

    with open("{}/client-registrar.yaml".format(newPackage), "w") as f:
        client_reg_template = client_reg_template.replace("{registration_port}", str(perm_port+1))
        f.write(client_reg_template)

    with open("{}/noerrors.txt".format(newPackage), "w") as f:
        f.write(no_errors)

    if not os.path.exists("{}/run.sh".format(newPackage)):
        with open("{}/run.sh".format(newPackage), "w") as f:
            run_template = run_template.replace("{entry_point}", str(gateway_ports[0]))
            f.write(run_template)

    else:
        with open("{}/run.sh".format(newPackage), "r") as f:
            filedata = f.read()
        newdata = re.sub(r"(localhost:)(\d+)", f"localhost:{str(gateway_ports[0])}", filedata)
        with open("{}/run.sh".format(newPackage), "w") as f:
            f.write(newdata)


    # Set the executable permissions on the bash script file
    os.chmod("{}/run.sh".format(newPackage), 0o755)

    
    # Write whitelist to package
    with open("{}/whitelist.txt".format(newPackage), "w") as f:
        f.write(whitelist)

    # Write release to package
    with open("{}/release.txt".format(newPackage), "w") as f:
        f.write(release_template)

    # Write mainnet to package
    with open("{}/mainnet.txt".format(newPackage), "w") as f:
        f.write(mainnet_template)

    # Write devnet to package
    with open("{}/devnet.txt".format(newPackage), "w") as f:
        f.write(devnet_template)

   # Write betanet to package
    with open("{}/betanet.txt".format(newPackage), "w") as f:
        f.write(betanet_template)


    # Write udb config
    with open("{}/udb.yaml".format(newPackage), "w") as f:
        udb_config = udb_config.replace("{permissioning_port}", str(perm_port))  \
            .replace("{udb_port}", str(udbPort))
        f.write(udb_config)

    with open("{}/udbContact.bin".format(newPackage), "w") as f:
        f.write(udb_contact)

    with open("{}/udbProto.json".format(newPackage), "w") as f:
        f.write(udb_proto)





# Count the number of packages previously created by counting
# run.sh files creates
def count_networks():
    current_dir = os.getcwd()
    count = 0
    for root, dirs, files in os.walk(current_dir):
        for file in files:
            if file == "permissioning.yaml":
                count += 1
    return count


def main(argv: Sequence[str] | None = None) -> int:
    network_count = count_networks()

    parser = argparse.ArgumentParser(description='Generate or count packages')
    subparsers = parser.add_subparsers(title='subcommands', dest='command')

    # "generate" subcommand
    generate_parser = subparsers.add_parser('generate', help='Generate packages')
    generate_parser.add_argument('--package', required=True, help='Name of the package')
    generate_parser.add_argument('--offset', type=int, default=0, help='Offset value')

    # "count" subcommand
    count_parser = subparsers.add_parser('count', help='Count packages')

    # parse the arguments
    args = parser.parse_args()

    if args.command == "count":
        print(f"Number of occurrences of run.sh in all subdirectories: {network_count}")
        return
    elif args.command == "generate":
        generate_server_side_config(network_count + args.offset, args.package)
    else:
        raise NotImplementedError(
            f"Command {args.command} does not exist.",
        )



if __name__ == "__main__":
    raise SystemExit(main())
