function Get-BgpList {
    param (
        [Parameter (Mandatory=$true, ValueFromPipeline=$True)]
        $edge
    )
    
    <#
    .SYNOPSIS
    ESGとDLRのBGP設定を一覧表示します

    .EXAMPLE
    $nsxa = Connect-NsxServer -Server nsx-a.ym.local -Username admin -Password P@ssw0rd
    $nsxb = Connect-NsxServer -Server nsx-b.ym.local -Username admin -Password P@ssw0rd
    $e = (Get-NsxEdge -Connection $nsxa) + (Get-NsxLogicalRouter -Connection $nsxa) + (Get-NsxEdge -Connection $nsxb) + (Get-NsxLogicalRouter -Connection $nsxb)
    $e | %{ Get-NsxBgp $_ } | ft -AutoSize
    $e | %{ Get-NsxBgp $_ } | Out-GridView
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

function Update-BgpTimer {
    <#
    .SYNOPSIS
    ESGとDLRのBGPタイマー設定を変更します

    .EXAMPLE
    (Get-NsxEdge) + (Get-NsxLogicalRouter) | Update-BgpTimer -keepAliveTimer 30 -holdDownTimer 90
    #>
    
    param (
        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
        $edge,
        $holdDownTimer = 180,
        $keepAliveTimer = 60
    )
    
    process {
        $bgp = $edge.features.routing.bgp
        if ( -not $bgp ){
            return
        }
        foreach ( $n in $bgp.bgpNeighbours.bgpNeighbour ) {
            $n.holdDownTimer = $holdDownTimer.ToString()
            $n.keepAliveTimer = $keepAliveTimer.ToString()
        }
        $body = $bgp.OuterXml
        $URI = "/api/4.0/edges/{0}/routing/config/bgp" -F $edge.id
        "Update BGP Timer of {0}" -F $edge.Name | Write-Host -ForegroundColor Cyan -NoNewLine
        invoke-nsxrestmethod -method "put" -uri $URI -body $body | Out-Null
        "`t`tOK" | Write-Host -ForegroundColor Green
    }
}

function Update-OspfTimer {
    <#
    .SYNOPSIS
    ESGとDLRのOspfタイマー設定を変更します

    .EXAMPLE
    (Get-NsxEdge) + (Get-NsxLogicalRouter) | Update-OspfTimer -deadInterval 40 -helloInterval 10
    #>
    
    param (
        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
        $edge,
        $deadInterval = 40,
        $helloInterval = 10,
        $priority = 128, 
        $cost = 1
    )
    
    process {
        $ospf = $edge.features.routing.ospf
        if ( -not $ospf ){
            return
        }
        foreach ( $i in $ospf.ospfInterfaces.ospfInterface ) {
            $i.deadInterval = $deadInterval.ToString()
            $i.helloInterval = $helloInterval.ToString()
            $i.priority = $priority.ToString()
            $i.cost = $cost.ToString()
        }
        $body = $ospf.OuterXml
        $URI = "/api/4.0/edges/{0}/routing/config/ospf" -F $edge.id
        "Update OSPF Timer of {0}" -F $edge.Name | Write-Host -ForegroundColor Cyan -NoNewLine
        invoke-nsxrestmethod -method "put" -uri $URI -body $body | Out-Null
        "`t`tOK" | Write-Host -ForegroundColor Green
    }
}
