# Create Logical Switches
function Deploy-LS(){
    foreach( $ls in ( gc .\ls.json | Out-String | ConvertFrom-Json ) ) {
        $lsConfig = @{
            TransportZone = ( Get-NsxTransportZone $ls.TransportZone )
            Name = $ls.Name
            ControlPlaneMode = $ls.ReplicationMode
            IpDiscoveryEnabled = $ls.EnableIpDiscovery
            MacLearningEnabled = $ls.EnableMacLearning
        }
        New-NsxLogicalSwitch @lsConfig -Verbose
    }
}


# Deploy ESG
function Get-ConnectedTo(){
    param (
        [Parameter (Mandatory=$true)]
        [string]$name
    )
    
    try {
        $connectedTo = Get-NsxLogicalSwitch -Name $name
        if ( -not $connectedTo ) {
            $connectedTo = Get-VDPortGroup -Name $name
        }
        $connectedTo
    } catch {}
}

function Deploy-ESG (){
    foreach( $esg in ( gc .\esg.json | Out-String | ConvertFrom-Json ) ) {
        $i = 0
        $vnics = foreach( $interface in $esg.interfaces ) {
            $interfaceConfig = @{
                Index = $i++
                Name = $interface.Name
                Type = $interface.Type
                ConnectedTo = ( Get-ConnectedTo $interface.ConnectedTo )
                PrimaryAddress = $interface.PrimaryIPAddress
                SecondaryAddress = $interface.SecondaryIPAddress
                SubnetPrefixLength = $interface.SubnetPrefixLength
                EnableProxyArp = $interface.EnableProxyARP
                EnableSendICMPRedirects = $interface.SendICMPRedirect
            }
            New-NsxEdgeInterfaceSpec @interfaceConfig -Verbose
        }

        $esgConfig = @{
            Name = $esg.Name
            Datastore = ( Get-Datastore $esg.Datastore )
            Password = $esg.Password
            Interface = $vnics
            FwEnabled = $esg.ConfigureFirewallDefaultPolicy
            FwDefaultPolicyAllow = ( $esg.DefaultTrafficPolicy -eq "Accept" )
            EnableSSH = $esg.EnableSSHaccess
            EnableHa = $esg.EnableHighAvailability
            VMFolder = if ( $esg.Folder ) { Get-Folder $esg.Folder } else { }
        }
        if ( $esg.Host -and ( $esg.Host[0].Length -gt 0 ) ) {
            $esgConfig.VMHost = $esg.Host
        }
        if ( $esg.HADatastore ) {
            $esgConfig.HADatastore = $esg.HADatastore
        }
        $cluster = Get-Cluster $esg.Cluster
        if ( $cluster.DrsEnabled ) {
            $esgConfig.Cluster = $cluster
        } else {
            $esgConfig.ResourcePool = $cluster | Get-ResourcePool -NoRecursion
        }
        if ( $esg.Syslog.SyslogServers ) {
            $esgConfig.EnableSyslog = $true
            $esgConfig.SyslogServer = $esg.Syslog.SyslogServers
            $esgConfig.SyslogProtocol = $esg.Syslog.Protocol
            # $esgConfig.LogLevel = $esg.EdgeControlLevelLogging
        }
        
        # Deploy
        New-NSXEdge @esgConfig -Verbose
        
        # Set Routing
        foreach ( $staticRoute in $esg.StaticRoute ) {
            if ( $staticRoute.Network ) {
                $staticRouteConfig = @{
                    Network = $staticRoute.Network
                    NextHop = $staticRoute.NextHop
                }
                Get-NsxEdge $esg.Name | Get-NsxEdgeRouting | New-NsxEdgeStaticRoute @staticRouteConfig -Confirm:$false -Verbose
            }
        }
        
        $ospfConfig = @{
            EnableOSPF = $esg.Ospf.Status
            RouterId = $esg.GlobalConfiguration.RouterId
            GracefulRestart = $esg.Ospf.EnableGracefulRestart
            DefaultOriginate = $esg.Ospf.DefaultOriginate
        }
        if ( $esg.Ospf.Status ) {
            Get-NsxEdge $esg.Name | Get-NsxEdgeRouting | Set-NsxEdgeOspf @ospfConfig -Confirm:$false -Verbose
        }
        
        $bgpConfig = @{
            EnableBGP = $esg.Bgp.Status
            RouterId = $esg.GlobalConfiguration.RouterId
            LocalAS = $esg.Bgp.LocalAS
            GracefulRestart = $esg.Bgp.EnableGracefulRestart
            DefaultOriginate = $esg.Bgp.DefaultOriginate
        }
        if ( $esg.Bgp.Status ) {
            Get-NsxEdge $esg.Name | Get-NsxEdgeRouting | Set-NsxEdgeBgp @bgpConfig -Confirm:$false -Verbose
        }
        
        foreach ( $neighbor in $esg.Bgp.Neighbors ) {
            $neighborConfig = @{
                IpAddress = $neighbor.IPAddress
                RemoteAS = $neighbor.RemoteAS
            }
            if ( $neighbor.Weight ) {
                $neighborConfig.Weight = $neighbor.Weight
            }
            if ( $neighbor.KeepAliveTime ) {
                $neighborConfig.KeepAliveTimer = $neighbor.KeepAliveTime
            }
            if ( $neighbor.HoldDownTime ) {
                $neighborConfig.HoldDownTimer = $neighbor.HoldDownTime
            }
            if ( $neighbor.Password ) {
                $neighborConfig.Password = $neighbor.Password
            }
            Get-NsxEdge $esg.Name | Get-NsxEdgeRouting | New-NsxEdgeBgpNeighbour @neighborConfig -Confirm:$false -Verbose
        }

        if ( $esg.GlobalConfiguration.ECMP ) {
            Get-NsxEdge $esg.Name | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableEcmp -Confirm:$false -Verbose
        }
        
        if ( $esg.RouteRedistribution ) {
            foreach ( $r in $esg.RouteRedistribution.RouteRedistributionTable ) {
                $rrconf = @{}

                if ( $r.Action ) { $rrconf.Action = $r.Action }
                if ( $r.PrefixName -and ( $r.PrefixName -notin ( "Any", "any" ) ) ) {
                    $rrconf.PrefixName = $r.PrefixName
                }
                
                if ( $r.AllowLearningFrom.OSPF ) { $rrconf.FromOspf = $true }
                if ( $r.AllowLearningFrom.BGP ) { $rrconf.FromBgp = $true }
                if ( $r.AllowLearningFrom.StaticRoutes ) { $rrconf.FromStatic = $true }
                if ( $r.AllowLearningFrom.Connected ) { $rrconf.FromConnected = $true }
                
                if ( $rrconf.FromOspf -or $rrconf.FromBgp -or $rrconf.FromStatic -or $rrconf.FromConnected ) {
                    if ( $esg.Ospf.Status ) {
                        Set-NsxEdgeRouting -EnableOspfRouteRedistribution -Confirm:$false -Verbose
                        New-NsxEdgeRedistributionRule -Learner ospf @rrconf -Confirm:$false -Verbose
                    } else {
                        Set-NsxEdgeRouting -EnableBgpRouteRedistribution -Confirm:$false -Verbose
                        New-NsxEdgeRedistributionRule -Learner bgp @rrconf -Confirm:$false -Verbose
                    }
                }
            }
        }
    }
}


# Deploy DLR

function Deploy-DLR(){
    foreach( $dlr in ( gc .\dlr.json | Out-String | ConvertFrom-Json ) ) {
        $vnics = foreach( $interface in $dlr.interfaces ) {
            $interfaceConfig = @{
                Name = $interface.Name
                Type = $interface.Type
                ConnectedTo = ( Get-ConnectedTo $interface.ConnectedTo )
                PrimaryAddress = $interface.PrimaryIPAddress
                SubnetPrefixLength = $interface.SubnetPrefixLength
            }
            New-NsxLogicalRouterInterfaceSpec @interfaceConfig -Verbose
        }

        $dlrConfig = @{
            Name = $dlr.Name
            Datastore = ( Get-Datastore $dlr.Datastore )
            # Password = $dlr.Password
            ManagementPortGroup = ( Get-ConnectedTo $dlr.ConnectedTo )
            Interface = $vnics
            # EnableSSH = $dlr.EnableSSHaccess
            EnableHa = $dlr.EnableHighAvailability
            Universal = $dlr.Universal
            EnableLocalEgress = $dlr.LocalEgress
        }
        if ( $dlr.Host -and ( $esg.Host[0].Length -gt 0 ) ) {
            $dlrConfig.VMHost = $esg.Host
        }
        if ( $dlr.HADatastore ) {
            $dlrConfig.HADatastore = $esg.HADatastore
        }
        $cluster = Get-Cluster $dlr.Cluster
        if ( $cluster.DrsEnabled ) {
            $dlrConfig.Cluster = $cluster
        } else {
            $dlrConfig.ResourcePool = $cluster | Get-ResourcePool
        }
        # if ( $dlr.Syslog.SyslogServers ) {
            # $dlrConfig.EnableSyslog = $true
            # $dlrConfig.SyslogServer = $dlr.Syslog.SyslogServers
            # $dlrConfig.SyslogProtocol = $dlr.Syslog.Protocol
            # $dlrConfig.LogLevel = $dlr.EdgeControlLevelLogging
        # }
        
        # Deploy
        New-NsxLogicalRouter @dlrConfig -Verbose

        # Set Routing
        foreach ( $staticRoute in $dlr.StaticRoute ) {
            if ( $staticRoute.Network ) {
                $staticRouteConfig = @{
                    Network = $staticRoute.Network
                    NextHop = $staticRoute.NextHop
                }
                Get-NsxLogicalRouter $dlr.Name | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterStaticRoute @staticRouteConfig -Confirm:$false -Verbose
            }
        }
        
        $ospfConfig = @{
            EnableOSPF = $dlr.Ospf.Status
            ProtocolAddress = $dlr.Ospf.ProtocolAddress
            ForwardingAddress = $dlr.Ospf.ForwardingAddress
            RouterId = $dlr.GlobalConfiguration.RouterId
            GracefulRestart = $dlr.Ospf.EnableGracefulRestart
        }
        if ( $dlr.Ospf.Status ) {
            Get-NsxLogicalRouter $dlr.Name | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterOspf @ospfConfig -Confirm:$false -Verbose
        }
        
        $bgpConfig = @{
            EnableBGP = $dlr.Bgp.Status
            RouterId = $dlr.GlobalConfiguration.RouterId
            LocalAS = $dlr.Bgp.LocalAS
            GracefulRestart = $dlr.Bgp.EnableGracefulRestart
        }
        if ( $dlr.Bgp.Status ) {
            Get-NsxLogicalRouter $dlr.Name | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterBgp @bgpConfig -Confirm:$false -Verbose
        }
        
        foreach ( $neighbor in $dlr.Bgp.Neighbors ) {
            $neighborConfig = @{
                IpAddress = $neighbor.IPAddress
                ForwardingAddress = $neighbor.ForwardingAddress
                ProtocolAddress = $neighbor.ProtocolAddress
                RemoteAS = $neighbor.RemoteAS
            }
            if ( $neighbor.Weight ) {
                $neighborConfig.Weight = $neighbor.Weight
            }
            if ( $neighbor.KeepAliveTime ) {
                $neighborConfig.KeepAliveTimer = $neighbor.KeepAliveTime
            }
            if ( $neighbor.HoldDownTime ) {
                $neighborConfig.HoldDownTimer = $neighbor.HoldDownTime
            }
            if ( $neighbor.Password ) {
                $neighborConfig.Password = $neighbor.Password
            }
            Get-NsxLogicalRouter $dlr.Name | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterBgpNeighbour @neighborConfig -Confirm:$false -Verbose
        }

        if ( $dlr.GlobalConfiguration.ECMP ) {
            Get-NsxLogicalRouter $dlr.Name | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -EnableEcmp -EnableOspfRouteRedistribution:$false -Confirm:$false -Verbose
        }
        
        Get-NsxLogicalRouter $dlr.Name | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -EnableOspfRouteRedistribution:$false -EnableBgpRouteRedistribution:$false -Confirm:$false -Verbose
        Get-NsxLogicalRouter $dlr.Name | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterRedistributionRule | Remove-NsxLogicalRouterRedistributionRule -Confirm:$false -Verbose
        if ( $dlr.RouteRedistribution ) {
            foreach ( $r in $dlr.RouteRedistribution.RouteRedistributionTable ) {
                $rrconf = @{}

                if ( $r.Action ) { $rrconf.Action = $r.Action.ToLower() }
                if ( $r.PrefixName -and ( $r.PrefixName -notin ( "Any", "any" ) ) ) {
                    $rrconf.PrefixName = $r.PrefixName
                }
                
                if ( $r.AllowLearningFrom.OSPF ) { $rrconf.FromOspf = $true }
                if ( $r.AllowLearningFrom.BGP ) { $rrconf.FromBgp = $true }
                if ( $r.AllowLearningFrom.StaticRoutes ) { $rrconf.FromStatic = $true }
                if ( $r.AllowLearningFrom.Connected ) { $rrconf.FromConnected = $true }
                
                if ( $rrconf.FromOspf -or $rrconf.FromBgp -or $rrconf.FromStatic -or $rrconf.FromConnected ) {
                    if ( $dlr.Ospf.Status ) {
                        Get-NsxLogicalRouter $dlr.Name | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -EnableOspfRouteRedistribution -Confirm:$false -Verbose
                        Get-NsxLogicalRouter $dlr.Name | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterRedistributionRule -Learner ospf @rrconf -Confirm:$false -Verbose
                    } else {
                        Get-NsxLogicalRouter $dlr.Name | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -EnableBgpRouteRedistribution -Confirm:$false -Verbose
                        Get-NsxLogicalRouter $dlr.Name | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterRedistributionRule -Learner bgp @rrconf -Confirm:$false -Verbose
                    }
                }
            }
        }
        
        # Set L2Bridge
        foreach ( $bridge in $dlr.Bridge ) {
            $bridgeConfig = @{
                Name = $bridge.Name
                PortGroup = ( Get-ConnectedTo $bridge.DistributedPortGroup )
                LogicalSwitch = ( Get-ConnectedTo $bridge.LogicalSwitch )
            }
            Get-NsxLogicalRouter $dlr.Name | Get-NsxLogicalRouterBridging | New-NsxLogicalRouterBridge @bridgeConfig -Verbose
        }
    }
}

function Deploy-NSX2(){
    Deploy-LS
    Deploy-ESG
    Deploy-DLR
}


# Delete Test Component
# Get-NsxLogicalRouter MKLRVM01 | Remove-NsxLogicalRouter -Confirm:$false
# Get-NsxEdge TKNEDG01 | Remove-NsxEdge -Confirm:$false
# Get-NsxLogicalSwitch | ?{$_.Name -like "Test*"} | Remove-NsxLogicalSwitch -Confirm:$false


# Delete All
# Get-NsxLogicalRouter | Remove-NsxLogicalRouter -Confirm:$false
# Get-NsxEdge | Remove-NsxEdge -Confirm:$false
# Get-NsxLogicalSwitch | Remove-NsxLogicalSwitch -Confirm:$false
# Get-NsxTransportZone | Remove-NsxTransportZone -Confirm:$false
# Get-NsxSegmentIdRange | Remove-NsxSegmentIdRange -Confirm:$false
# Get-Cluster | ?{ (Get-NsxClusterStatus $_).installed -eq "true" } | Remove-NsxClusterVxlanConfig -Confirm:$false
# Get-NsxVdsContext | Remove-NsxVdsContext -Confirm:$false
# remove controllers
# Get-NsxIpPool | Remove-NsxIpPool -Confirm:$false
