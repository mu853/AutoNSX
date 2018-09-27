function Get-BgpList {
    param (
        [Parameter (Mandatory=$true, ValueFromPipeline=$True)]
        $edge
    )
    
    <#
    .SYNOPSIS
    ESG‚ÆDLR‚ÌBGPÝ’è‚ðˆê——•\Ž¦‚µ‚Ü‚·

    .EXAMPLE
    $nsxa = Connect-NsxServer -Server nsx-a.ym.local -Username admin -Password P@ssw0rd
    $nsxb = Connect-NsxServer -Server nsx-b.ym.local -Username admin -Password P@ssw0rd
    $e = (Get-NsxEdge -Connection $nsxa) + (Get-NsxLogicalRouter -Connection $nsxa) + (Get-NsxEdge -Connection $nsxb) + (Get-NsxLogicalRouter -Connection $nsxb)
    $e | %{ Get-NsxBgp $_ } | ft -AutoSize
    #>

    process {
        $r = $null
        if( $edge.type -eq "gatewayServices" ){
            $r = $edge | Get-NsxEdgeRouting
        }else{
            $r = $edge | Get-NsxLogicalRouterRouting
        }

        [PSCustomObject]@{
            Name = $edge.Name
            ECMP = $r.routingGlobalConfig.ecmp
            LocalAS = $r.bgp.localASNumber
            Redist = $r.bgp.redistribution.enabled
            IPAddress = ""
            RemoteAS = ""
            Weight = ""
            HoldDown = ""
            KeepAlive = ""
        }

        foreach( $n in $r.bgp.bgpNeighbours.bgpNeighbour | sort { [Version]$_.ipAddress } ){
            [PSCustomObject]@{
                Name = ""
                ECMP = ""
                LocalAS = ""
                Redist = ""
                IPAddress = $n.ipAddress
                RemoteAS = $n.remoteASNumber
                Weight = $n.weight
                HoldDown = $n.holdDownTimer
                KeepAlive = $n.keepAliveTimer
            }
        }
    }
}

