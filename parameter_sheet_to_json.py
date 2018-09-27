import json, sys, re
import extractor as ex
import openpyxl as px

def convert_ls(ws_data):
    ls_list = []

    for d in ws_data[0]["Logical Switch"]:
        ls = {}
        name = d["Name"]
        if not name: continue
        ls["Name"] = name
        ls["Dscription"] = d["Description"]
        ls["TransportZone"] = d["Transport Zone"]
        ls["ReplicationMode"] = d["Replication mode"].upper() + "_MODE"
        ls["EnableIpDiscovery"] = d["Enable IP Discovery"]
        ls["EnableMacLearning"] = d["Enable MAC Learning"]
        ls_list.append(ls)
 
    return ls_list

def select_data(ws_data, name, name_key = "Name"):
    d = list(filter(lambda e: e[name_key] == name, ws_data))
    if len(d) < 1:
        print("Data matches to {} is not found.".format(name), file = sys.stderr)
        return []
    if len(d) > 1:
        print("Data matches to {} is duplicated.".format(name), file = sys.stderr)
    return d[0]

def convert_esg(ws_data):
    esg_list = []

    for d in ws_data:
        esg = {}
        
        p = d["Name and description"]
        esg["Name"] = p["Name"]
        esg["Hostname"] = p["Hostname"]
        esg["EnableHighAvailability"] = p["Enable High Availability"]

        p = d["Settings"]
        esg["Password"] = p["Password"]
        esg["EnableSSHaccess"] = p["Enable SSH access"]
        esg["EnableFIPSmode"] = p["Enable FIPS mode"]
        esg["EnableAutoRuleGeneration"] = p["Enable auto rule generation"]
        esg["EdgeControlLevelLogging"] = p["Edge Control Level Logging"]

        p = d["Configure deployment"]
        esg["Datacenter"] = p["Datacenter"]
        esg["ApplianceSize"] = re.sub(r"[- ]", "", p["Appliance Size"]).lower()
        appliances = p["NSX Edge Appliance"]
        esg["Cluster"] = appliances[0]["Cluster/Resource Pool"]
        esg["Datastore"] = appliances[0]["Datastore"]
        esg["Host"] = appliances[0]["Host"]
        esg["Folder"] = appliances[0]["Folder"]
        if not esg["Folder"]: esg["Folder"] = "vm"
        if len(appliances) > 1:
            esg["Host"] = [esg["Host"], appliances[1]["Host"]]
            esg["HADatastore"] = appliances[1]["Datastore"]
        
        p = d["Default gateway settings"]
        esg["ConfigureDefaultGateway"] = p["Configure Default Gateway"]
        esg["GatewayvNIC"] = p["vNIC"]
        esg["GatewayIP"] = p["Gateway IP"]
        esg["GatewayMTU"] = p["MTU"]
        esg["GatewayAdminDistance"] = p["Admin Distance"]

        p = d["Firewall and HA"]
        esg["ConfigureFirewallDefaultPolicy"] = p["Configure Firewall default policy"]
        esg["DefaultTrafficPolicy"] = p["Default Traffic Policy"]
        esg["DefaultFirewallLogging"] = p["Logging"]
        esg["HAvNIC"] = p["vNIC"]
        esg["HADeclareDeadTime"] = p["Declare Dead Time"]
        esg["HAManagementIPs"] = p["Management IPs"]

        esg_list.append(esg)

    return esg_list


def convert_esg_settings(ws_data, esg_name):
    d = select_data(ws_data, esg_name, "Edge Name")

    interfaces = []
    nics = d["Interfaces"]["vNIC"]
    for n in nics:
        interface = {}
        interface["Name"] = n["Name"]
        interface["Type"] = n["Type"]
        interface["ConnectedTo"] = n["Connected To"]
        config = n["Configure Subnets"]
        interface["PrimaryIPAddress"] = config["PrimaryIP Address"]
        interface["SecondaryIPAddress"] = config["SecondaryIP Addresses"]
        interface["SubnetPrefixLength"] = config["Subnet Prefix Length"]
        interface["MTU"] = config["MTU"]
        option = config["Options"]
        interface["EnableProxyARP"] = option["Enable Proxy ARP"]
        interface["SendICMPRedirect"] = option["Send ICMP Redirect"]
        interface["ReversePathFilter"] = option["Reverse Path Filter"]
        interfaces.append(interface)

    syslog = {}
    p = d["Configuration"]
    s = p["Details"]["Syslog Servers"]
    if s["Syslog Server 1"] or s["Syslog Server 2"]:
        syslog["SyslogServers"] = []
        if s["Syslog Server 1"]: syslog["SyslogServers"].append(s["Syslog Server 1"])
        if s["Syslog Server 2"]: syslog["SyslogServers"].append(s["Syslog Server 2"])
    syslog["Protocol"] = s["Protocol"]
        
    return [syslog, interfaces]

def convert_esg_routing(ws_data, esg_name):
    d = select_data(ws_data, esg_name, "Edge Name")
    
    global_configuration = {}
    p = d["Global Configuration"]
    global_configuration["RouterId"] = p["Dynamic Routing Configuration"]["Router ID"]
    global_configuration["ECMP"] = p["ECMP"]
    default_gateway = {}
    default_gateway["vNIC"] = p["Default Gateway"]["vNIC"]
    default_gateway["GatewayIP"] = p["Default Gateway"]["Gateway IP"]
    default_gateway["MTU"] = p["Default Gateway"]["MTU"]
    default_gateway["AdminDistance"] = p["Default Gateway"]["Admin Distance"]
    global_configuration["DefaultGateway"] = default_gateway

    static_routes = []
    for r in d["Static routes"]["route"]:
        static_route = {}
        static_route["Network"] = r["Network"]
        static_route["NextHop"] = r["Next Hop"]
        static_routes.append(static_route)

    ospf = {}
    p = d["OSPF"]
    ospf["Status"] = p["Status"]
    ospf["GracefulRestart"] = p["Graceful Restart"]
    ospf["DefaultOriginate"] = p["Default Originate"]

    bgp = {}
    p = d["BGP"]
    bgp["Status"] = p["Status"]
    bgp["LocalAS"] = p["Local AS"]
    bgp["GracefulRestart"] = p["Graceful Restart"]
    bgp["DefaultOriginate"] = p["Default Originate"]
    neighbors = []
    for n in p["Neighbors"]["Neighbor"]:
        neighbor = {}
        neighbor["IPAddress"] = n["IP Address"]
        neighbor["RemoteAS"] = n["Remote AS"]
        neighbor["RemovePrivateAS"] = n["Remove Private AS"]
        neighbor["Weight"] = n["Weight"]
        neighbor["KeepAliveTime"] = n["Keep Alive Time"]
        neighbor["HoldDownTime"] = n["Hold Down Time"]
        neighbor["Password"] = n["Password"]
        neighbors.append(neighbor)
    bgp["Neighbors"] = neighbors

    route_redistribution = {}
    p = d["Route Redistribution"]
    
    ip_prefixes = []
    for pf in p["IP Prefixes"]["IP Prefix"]:
        ip_prefix = {}
        ip_prefix["Name"] = pf["Name"]
        ip_prefix["IP/Network"] = pf["IP/Network"]
        ip_prefixes.append(ip_prefix)
    route_redistribution["IPPrefixes"] = ip_prefixes
    
    route_redistribution_table = []
    for r in p["Route Redistribution Table"]["Redistribution Criteria"]:
        redistribution_criteria = {}
        redistribution_criteria["PrefixName"] = r["Prefix Name"]
        redistribution_criteria["LearnerProtocol"] = r["Learner Protocol"]
        redistribution_criteria["AllowLearningFrom"] = {}
        redistribution_criteria["AllowLearningFrom"]["OSPF"] = r["Allow Learning from"]["OSPF"]
        redistribution_criteria["AllowLearningFrom"]["BGP"] = r["Allow Learning from"]["BGP"]
        redistribution_criteria["AllowLearningFrom"]["StaticRoutes"] = r["Allow Learning from"]["Static Routes"]
        redistribution_criteria["AllowLearningFrom"]["Connected"] = r["Allow Learning from"]["Connected"]
        redistribution_criteria["Action"] = r["Action"]
        route_redistribution_table.append(redistribution_criteria)
    route_redistribution["RouteRedistributionTable"] = route_redistribution_table
    
    return [global_configuration, static_routes, ospf, bgp, route_redistribution]

def convert_dlr(ws_data):
    dlr_list = []
    
    for d in ws_data:
        dlr = {}

        p = d["Name and description"]
        dlr["Universal"] = ( p["Install Type"] == "Universal Logical (Distributed) Router" )
        dlr["LocalEgress"] = p["Local Egress"]
        dlr["Name"] = p["Name"]
        dlr["Hostname"] = p["Hostname"]
        dlr["Hostname"] = p["Hostname"]
        dlr["EnableHighAvailability"] = p["Enable High Availability"]

        p = d["Settings"]
        dlr["Password"] = p["Password"]
        dlr["EnableSSHaccess"] = p["Enable SSH access"]
        dlr["EnableFIPSmode"] = p["Enable FIPS mode"]
        dlr["EdgeControlLevelLogging"] = p["Edge Control Level Logging"]

        p = d["Configure deployment"]
        dlr["Datacenter"] = p["Datacenter"] 
        appliances = p["DLR Appliance"]
        dlr["Cluster"] = appliances[0]["Cluster/Resource Pool"]
        dlr["Datastore"] = appliances[0]["Datastore"]
        dlr["Host"] = appliances[0]["Host"]
        dlr["Folder"] = appliances[0]["Folder"]
        if not esg["Folder"]: esg["Folder"] = "vm"
        if len(appliances) > 1:
            dlr["Host"] = [dlr["Host"], appliances[1]["Host"]]
            dlr["HADatastore"] = appliances[1]["Datastore"]

        p = d["Configure interfaces"]
        haconfig = p["HA Interface Configuration"]
        dlr["ConnectedTo"] = haconfig["Connected To"]
        dlr["PrimaryIPAddress"] = haconfig["Primary IP Address"]
        dlr["SubnetPrefixLength"] = haconfig["Subnet Prefix Length"]

        p = d["Default gateway settings"]
        dlr["ConfigureDefaultGateway"] = p["Configure Default Gateway"]
        dlr["GatewayvNIC"] = p["vNIC"]
        dlr["GatewayIP"] = p["Gateway IP"]
        dlr["GatewayMTU"] = p["MTU"]
        dlr["GatewayAdminDistance"] = p["Admin Distance"]
        
        dlr_list.append(dlr)

    return dlr_list

def convert_dlr_settings(ws_data, dlr_name):
    d = select_data(ws_data, dlr_name, "DLR Name")
    
    interfaces = []
    nics = d["Interfaces"]["vNIC"]
    for n in nics:
        interface = {}
        name = n["Name"]
        if not name: continue
        interface["Name"] = name
        interface["Type"] = n["Type"]
        interface["ConnectedTo"] = n["Connected To"]
        config = n["Configure Subnets"]
        interface["PrimaryIPAddress"] = config["PrimaryIP Address"]
        interface["SubnetPrefixLength"] = config["Subnet Prefix Length"]
        interface["MTU"] = config["MTU"]
        interfaces.append(interface)

    syslog = {}
    p = d["Configuration"]
    s = p["Details"]["Syslog Servers"]
    if s["Syslog Server 1"] or s["Syslog Server 2"]:
        syslog["SyslogServers"] = []
        if s["Syslog Server 1"]: syslog["SyslogServers"].append(s["Syslog Server 1"])
        if s["Syslog Server 2"]: syslog["SyslogServers"].append(s["Syslog Server 2"])
    syslog["Protocol"] = s["Protocol"]

    return [syslog, interfaces]

def convert_dlr_routing(ws_data, dlr_name):
    d = select_data(ws_data, dlr_name, "DLR Name")
    
    global_configuration = {}
    p = d["Global Configuration"]
    global_configuration["RouterId"] = p["Dynamic Routing Configuration"]["Router ID"]
    global_configuration["ECMP"] = p["ECMP"]
    default_gateway = {}
    default_gateway["vNIC"] = p["Default Gateway"]["vNIC"]
    default_gateway["GatewayIP"] = p["Default Gateway"]["Gateway IP"]
    default_gateway["MTU"] = p["Default Gateway"]["MTU"]
    global_configuration["DefaultGateway"] = default_gateway

    static_routes = []
    for r in d["Static routes"]["route"]:
        static_route = {}
        static_route["Network"] = r["Network"]
        static_route["NextHop"] = r["Next Hop"]
        static_routes.append(static_route)

    ospf = {}
    p = d["OSPF"]
    ospf["Status"] = p["Status"]
    ospf["ProtocolAddress"] = p["Protocol Address"]
    ospf["ForwardingAddress"] = p["Forwarding Address"]
    ospf["GracefulRestart"] = p["Graceful Restart"]
    
    bgp = {}
    p = d["BGP"]
    bgp["Status"] = p["Status"]
    bgp["GracefulRestart"] = p["Graceful Restart"]
    bgp["LocalAS"] = p["Local AS"]
    neighbors = []
    for n in p["Neighbors"]["Neighbor"]:
        neighbor = {}
        neighbor["Interface"] = n["Interface"]
        neighbor["IPAddress"] = n["IP Address"]
        neighbor["ForwardingAddress"] = n["Forwarding Address"]
        neighbor["ProtocolAddress"] = n["Protocol Address"]
        neighbor["RemoteAS"] = n["Remote AS"]
        neighbor["Weight"] = n["Weight"]
        neighbor["KeepAliveTime"] = n["Keep Alive Time"]
        neighbor["HoldDownTime"] = n["Hold Down Time"]
        neighbor["Password"] = n["Password"]
        neighbors.append(neighbor)
    bgp["Neighbors"] = neighbors
    
    route_redistribution = {}
    p = d["Route Redistribution"]
    
    ip_prefixes = []
    for pf in p["IP Prefixes"]["IP Prefix"]:
        ip_prefix = {}
        ip_prefix["Name"] = pf["Name"]
        ip_prefix["IP/Network"] = pf["IP/Network"]
        ip_prefixes.append(ip_prefix)
    route_redistribution["IPPrefixes"] = ip_prefixes
    
    route_redistribution_table = []
    for r in p["Route Redistribution Table"]["Redistribution Criteria"]:
        redistribution_criteria = {}
        redistribution_criteria["PrefixName"] = r["Prefix Name"]
        redistribution_criteria["LearnerProtocol"] = r["Learner Protocol"]
        redistribution_criteria["AllowLearningFrom"] = {}
        redistribution_criteria["AllowLearningFrom"]["OSPF"] = r["Allow Learning from"]["OSPF"]
        redistribution_criteria["AllowLearningFrom"]["BGP"] = r["Allow Learning from"]["BGP"]
        redistribution_criteria["AllowLearningFrom"]["StaticRoutes"] = r["Allow Learning from"]["Static Routes"]
        redistribution_criteria["AllowLearningFrom"]["Connected"] = r["Allow Learning from"]["Connected"]
        redistribution_criteria["Action"] = r["Action"]
        route_redistribution_table.append(redistribution_criteria)
    route_redistribution["RouteRedistributionTable"] = route_redistribution_table
    
    return [global_configuration, static_routes, ospf, bgp, route_redistribution]

def convert_dlr_bridge(ws_data, dlr_name):
    d = select_data(ws_data, dlr_name, "DLR Name")

    bridges = []
    for b in d["Bridges"]["Bridge"]:
        bridge = {}
        name = b["Name"]
        if not name: continue
        bridge["Name"] = name
        bridge["LogicalSwitch"] = b["Logical Switch"]
        bridge["DistributedPortGroup"] = b["Distributed Port Group"]
        bridges.append(bridge)

    return bridges



if len(sys.argv) < 2:
    print("usage {} <paramenter_sheet.xlsx> [<output directory>]".format(sys.argv[0]))
    exit()

output_dir = "."
if len(sys.argv) > 2:
    output_dir = sys.argv[2]

parameter_sheet = sys.argv[1]

wb = px.load_workbook(parameter_sheet, data_only = True)
ws_data_ls = ex.extract(wb['Logical Switches'], sheet_type = "MultiColumn2")
ws_data_edge1 = ex.extract(wb['NSX Edge Deploy'])
ws_data_edge2 = ex.extract(wb['NSX Edge Settings'])
ws_data_edge3 = ex.extract(wb['NSX Edge Routing'])
ws_data_dlr1 = ex.extract(wb['DLR Deploy'])
ws_data_dlr2 = ex.extract(wb['DLR Settings'], sheet_type = "MultiColumn")
ws_data_dlr3 = ex.extract(wb['DLR Routing'])
ws_data_dlr4 = ex.extract(wb['DLR Bridding'], sheet_type = "MultiColumn")
wb.close()

# LS settings
ls_list = convert_ls(ws_data_ls)

# ESG settings
esg_list = convert_esg(ws_data_edge1)
for esg in esg_list:
    esg_name = esg["Name"]
    esg["Syslog"], esg["Interfaces"] = convert_esg_settings(ws_data_edge2, esg_name)
    esg["GlobalConfiguration"], esg["StaticRoute"], esg["Ospf"], esg["Bgp"], esg["RouteRedistribution"] = convert_esg_routing(ws_data_edge3, esg_name)

# DLR settings
dlr_list = convert_dlr(ws_data_dlr1)
for dlr in dlr_list:
    dlr_name = dlr["Name"]
    dlr["Syslog"], dlr["Interfaces"] = convert_dlr_settings(ws_data_dlr2, dlr_name)
    dlr["GlobalConfiguration"], dlr["StaticRoute"], dlr["Ospf"], dlr["Bgp"], dlr["RouteRedistribution"] = convert_dlr_routing(ws_data_dlr3, dlr_name)
    dlr["Bridge"] = convert_dlr_bridge(ws_data_dlr4, dlr_name)

with open((output_dir + "/ls.json"), "w")  as f: f.write(json.dumps(ls_list,  ensure_ascii=False, indent=4, sort_keys=True, separators=(',', ': ')))
with open((output_dir + "/esg.json"), "w") as f: f.write(json.dumps(esg_list, ensure_ascii=False, indent=4, sort_keys=True, separators=(',', ': ')))
with open((output_dir + "/dlr.json"), "w") as f: f.write(json.dumps(dlr_list, ensure_ascii=False, indent=4, sort_keys=True, separators=(',', ': ')))

