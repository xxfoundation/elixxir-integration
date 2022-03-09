import os
import string
import random

def randomString(stringLength=4):
    letters = string.ascii_lowercase
    return ''.join(random.choice(letters) for i in range(stringLength))

nodes = int(input("Total number of nodes: "))
minStart = int(input("Minimum number of nodes online to start network: "))
teamSize = int(input("Size of each team: "))

# Array of integers for ports of each server and gateway in the network
gateway_ports = []
node_ports = []
node_regCodes = []

server_template = ""
with open("server.yaml") as f:
    server_template = f.read()

gateway_template = ""
with open("gateway.yaml") as f:
    gateway_template = f.read()

reg_template = ""
with open("permissioning.yaml") as f:
    reg_template = f.read()

reg_json_template = ""
with open("registration.json") as f:
    reg_json_template = f.read()

# Generate a list of all ports servers and gateways occupy. Doing this as a 
# separate step because their configs need every one listed, and generating them
# once is lighter on CPU cycles.
for i in range(nodes):
    gateway_ports.append(8200+i)
    node_ports.append(11200+i)

    regCode = randomString()
    # If this regCode is already in the list, we loop until we get one that 
    # isn't
    while regCode in node_regCodes:
        regCode = randomString()
    node_regCodes.append(regCode)

# Generate server and gateway configs
for i in range(nodes):
    with open("../server-{}.yaml".format(i), 'w') as f:
        # Array of strings defining node and gateway IPs and ports
        node_addrs = []
        node_addrs.append("\"{}\"".format(node_ports[i]))
        # TODO: replace iplistoutput, idf, metrics log
        # Create a new config based on template
        s_config = server_template.replace("server-1", "server-" + str(i)) \
            .replace("gateway-1", "gateway-" + str(i)) \
            .replace("metrics-server-0", "metrics-server-" + str(i)) \
            .replace("ipList-1", "ipList-" + str(i)) \
            .replace("{NODE_ADDR}", "\r\n".join(node_addrs)) \
            .replace("{DB_ADDR}", "".join(["\"\""])) \
            .replace("AAAA", node_regCodes[i]) \
            .replace("nodeID-0.json", "nodeID-"+str(i)+".json") \
            .replace("11200", str(node_ports[i])) \
            .replace("results/servers/server-0", "results/servers/server-" + str(i)) \
            .replace("errServer-0.txt", "errServer-"+str(i)+".txt")
        f.write(s_config)

    with open("../gateway-{}.yaml".format(i), 'w') as f:
        # Array of strings defining node and gateway IPs and ports
        node_addrs = []
        node_addrs.append("0.0.0.0:{}".format(node_ports[i]))

        # Create a new config based on template
        g_config = gateway_template.replace("server-1", "server-" + str(i)) \
            .replace("gateway-0", "gateway-" + str(i)) \
            .replace("8200", str(gateway_ports[i])) \
            .replace("{NODE_ADDR}", "".join(node_addrs)) \
            .replace("gatewayIDF-0", "gatewayIDF-" + str(i))

        f.write(g_config)


# Generate permissioning stuff
with open("../registration.json", "w") as f:
    config = reg_json_template.replace("{teamSize}", str(teamSize))
    f.write(config)
with open("../permissioning-actual.yaml", "w") as f:
    config = reg_template.replace("{minStart}", str(minStart))
    f.write(config)

# Generate server regCodes file
with open("../regCodes.json", "w") as f:
    f.write("[")
    countries = ["CR", "GB", "SK", "HR", "IQ", "RU"]
    for i in range(nodes):
        f.write("{\"RegCode\": \"" + node_regCodes[i] + "\", \"Order\": \"" + \
            countries[i % len(countries)] + "\"}")
        # If not the last element, write a comma
        if i is not (nodes - 1): 
            f.write(",")

    f.write("]")
