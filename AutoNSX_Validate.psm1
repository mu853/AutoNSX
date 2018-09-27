Set-PSDebug -Strict
$ErrorActionPreference = "Stop"

function assert(){
    param(
        $condition,
        [string]$message
    )

    if ( -not $condition ) {
        throw $message
    }
}

function assert_should(){
    param(
        $condition,
        [string]$message
    )

    if ( -not $condition ) {
        $message | Write-Host -ForegroundColor Cyan
    }
}

function assert_exists(){
    param(
        $object,
        $name
    )

    if ( $object ) {
        "$name is Found" | Write-Host -ForegroundColor Green
    } else {
        "$name is Not Found" | Write-Host -ForegroundColor Red
    }
}

function assert_not_exists(){
    param(
        $object,
        $name
    )

    if ( $object ) {
        "$name is already exists" | Write-Host -ForegroundColor Red
    }
}

function Get-ConnectedTo(){
    param (
        [Parameter (Mandatory=$true)]
        [string]$name
    )
    
    try {
        $connectedTo = $null
        #if ( Test-Path $global:DefaultVIServer ) {
            $connectedTo = Get-NsxLogicalSwitch -Name $name -ErrorAction Ignore
        #}
        if ( -not $connectedTo ) {
            $connectedTo = Get-VDPortGroup -Name $name -ErrorAction Ignore
        }
        $connectedTo
    } catch {
        throw "Logical Switch or Distributed PortGroup named $name is Not Found."
    }
}

function Validate-IPAddress ( $ipaddress ) {
    assert -condition $ipaddress -message "IPアドレスが設定されていません"
    assert -condition ( ( $ipaddress -as [System.Net.IPAddress] ) -ne $null ) -message "IPアドレス $ipaddress は形式が正しくありません"
}

function Validate-CIDR ( $cidr ) {
    assert -condition $cidr -message "CIDR値が設定されていません"
    $tmp = $cidr -split "/"
    assert -condition ( $tmp.length -eq 2 ) -message "CIDR $cidr の形式が不正です"
    Validate-IPAddress ( $tmp[0] )
    assert -condition [int]::TryParse( $tmp[1], [ref]$null ) -message "CIDR $cidr の形式が不正です"

    $prefixLength = [int]$tmp[1]
    assert -condition  ( ( $prefixLength -ge 0 ) -and ( $prefixLength -le 32 ) ) -message "CIDR $cidr の形式が不正です"
}

function Validate-NSX () {
    param (
        $confdir = "."
    )
    
    cd $confdir

    "[Validate Logical Switches]" | Write-Host -ForegroundColor Yellow
    $ls = gc .\ls.json | Out-String | ConvertFrom-Json
    foreach ( $l in $ls ) {
        assert_not_exists ( Get-NsxLogicalSwitch $l.Name ) ( "LogicalSwitch [{0}]" -F $l.Name )
    }

    $ls.TransportZone | Get-Unique | %{
        assert_exists ( Get-NsxTransportZone $_ ) ( "TransportZone [{0}]" -F $_ )
    }


    foreach ( $e in (gc .\esg.json | Out-String | ConvertFrom-Json) ) {
        ( "[Validate ESG ({0})]" -F $e.Name ) | Write-Host -ForegroundColor Yellow
        try{
            assert_not_exists ( Get-VM ( "{0}-[01]" -F $e.Name ) -ErrorAction Ignore ) ( "VM [{0}]" -F $e.Name )
            assert -condition ( $e.Datacenter ) -message "Datacenterが指定されていません"
            assert_exists ( Get-Datacenter $e.Datacenter -ErrorAction Ignore ) ( "Datacenter [{0}]" -F $e.Datacenter )
            assert -condition ( $e.Cluster ) -message "Clusterが指定されていません"
            assert_exists ( Get-Cluster $e.Cluster -ErrorAction Ignore )       ( "Cluster [{0}]" -F $e.Cluster )
            assert -condition ( $e.Datastore ) -message "Datastoreが指定されていません"
            assert_exists ( Get-Datastore $e.Datastore -ErrorAction Ignore )   ( "Datastore [{0}]" -F $e.Datastore )
            assert_should -condition ( $e.HADatastore ) -message "HADatastoreが指定されていません"
            if ( $e.HADatastore ){
                assert_exists ( Get-Datastore $e.HADatastore -ErrorAction Ignore ) ( "Datastore [{0}]" -F $e.HADatastore )
            }
            if ( $e.VMHost -and $e.VMHost[0].Length -gt 0 ) {
                assert_exists ( Get-VMHost $e.Host -ErrorAction Ignore )   ( "VMHost [{0}]" -F $e.Host )
            }
            if ( $e.Folder ) {
                assert_exists ( Get-Folder $e.Folder -ErrorAction Ignore ) ( "Folder [{0}]" -F $e.Folder )
            }

            assert -condition ( $e.Password.length -ge 12 ) -message "CLIパスワードが設定されていないか、文字数が不足しています"
            assert_should -condition $e.EnableHighAvailability -message "HAが有効化されていません"
            assert_should -condition ( -not $e.EnableFIPSmode ) -message "FIPSモードが有効になっています"
            assert_should -condition $e.EnableAutoRuleGeneration -message "自動ルール生成が無効になっています"
            assert_should -condition $e.EnableSSHaccess -message "SSHが有効化されていません"
            assert_should -condition ( $e.HAvNIC -ne "any" ) -message "HAハートビート用NICが指定されていません"
            assert_should -condition $e.Syslog.SyslogServers -message "Syslogサーバーが設定されていません"
            if ( $e.Syslog.SyslogServers ) {
                $e.Syslog.SyslogServers | %{
                    Validate-IPAddress ( $_ )
                }
            }

            $uplink = $e.Interfaces | ?{ $_.Type -eq "Uplink" }
            assert -condition $uplink -message "Uplink I/F が設定されていません"
            $e.Interfaces | %{
                if ( $_.ConnectedTo -in $ls.name ) {
                    # "{0} は ls.json に含まれます" -F $_.ConnectedTo | Write-Host -ForegroundColor Green
                } else {
                    assert_exists ( Get-ConnectedTo ( $_.ConnectedTo ) ) ( "Network [{0}]" -F $_.ConnectedTo )
                }
                if ( $_.PrimaryIPAddress ) {
                    Validate-IPAddress ( $_.PrimaryIPAddress )
                }
            }

            if ( $e.ConfigureDefaultGateway ){
                assert -condition $e.GatewayIP -message "デフォルトゲートウェイのIPアドレスが設定されていません"
                assert -condition $e.GatewayMTU -message "デフォルトゲートウェイのMTUが設定されていません"
                assert -condition $e.AdminDistance -message "デフォルトゲートウェイの管理ディスタンスが設定されていません"
                Validate-IPAddress ( $e.GatewayIP )
            }

            if ( $e.StaticRoute.Network.Length -gt 0 ) {
                $e.StaticRoute | %{
                    Validate-CIDR ( $_.Network )
                    Validate-IPAddress ( $_.NextHop )
                }
            }
        } catch {
            $error[0].Exception.ToString() | Write-Host -ForegroundColor Red
        }
    }

    foreach ( $e in (gc .\dlr.json | Out-String | ConvertFrom-Json) ) {
        ( "[Validate DLR ({0})]" -F $e.Name ) | Write-Host -ForegroundColor Yellow
        try{
            assert_not_exists ( Get-VM ( "{0}-[01]" -F $e.Name ) -ErrorAction Ignore ) ( "VM [{0}]" -F $e.Name )
            assert -condition ( $e.Datacenter ) -message "Datacenterが指定されていません"
            assert_exists ( Get-Datacenter $e.Datacenter ) ( "Datacenter [{0}]" -F $e.Datacenter )
            $cl = Get-Cluster $e.Cluster -ErrorAction Ignore
            assert -condition ( $e.Cluster ) -message "Clusterが指定されていません"
            assert_exists ( $cl )                          ( "Cluster [{0}]" -F $e.Cluster )
            assert -condition ( $e.Datastore ) -message "Datastoreが指定されていません"
            assert_exists ( Get-Datastore $e.Datastore -ErrorAction Ignore )   ( "Datastore [{0}]" -F $e.Datastore )
            assert_should ( $e.HADatastore ) -message "HADatastoreが指定されていません"
            if ( $e.HADatastore ){
                assert_exists ( Get-Datastore $e.HADatastore -ErrorAction Ignore ) ( "Datastore [{0}]" -F $e.HADatastore )
            }
            if ( $e.VMHost -and $e.Host[0].Length -gt 0 ) {
                assert_exists ( Get-VMHost $e.Host -ErrorAction Ignore )   ( "VMHost [{0}]" -F $e.Host )
            }
            if ( $e.Folder ) {
                assert_exists ( Get-Folder $e.Folder -ErrorAction Ignore ) ( "Folder [{0}]" -F $e.Folder )
            }

            assert -condition ( $e.Password.length -ge 12 ) -message "CLIパスワードが設定されていないか、文字数が不足しています"
            assert_should -condition $e.EnableHighAvailability -message "HAが有効化されていません"
            assert_should -condition ( -not $e.EnableFIPSmode ) -message "FIPSモードが有効になっています"
            assert_should -condition $e.EnableSSHaccess -message "SSHが有効化されていません"
            assert_should -condition ( $e.ConnectedTo ) -message "HAインターフェイスが指定されていません"
            assert_exists ( Get-ConnectedTo ( $e.ConnectedTo ) ) ( "Network [{0}]" -F $e.ConnectedTo )
            if ( $e.PrimaryIPAddress ) {
                Validate-IPAddress ( $e.PrimaryIPAddress )
            }
            assert_should -condition $e.Syslog.SyslogServers -message "Syslogサーバーが設定されていません"
            if ( $e.Syslog.SyslogServers ) {
                $e.Syslog.SyslogServers | %{
                    Validate-IPAddress ( $_ )
                }
            }

            $uplink = $e.Interfaces | ?{ $_.Type -eq "Uplink" }
            assert -condition $uplink -message "Uplink I/F が設定されていません"
            $e.Interfaces | %{
                if ( $_.ConnectedTo -in $ls.name ) {
                    # "{0} は ls.json に含まれます" -F $_.ConnectedTo | Write-Host -ForegroundColor Green
                } else {
                    assert_exists ( Get-ConnectedTo ( $_.ConnectedTo ) ) ( "Network [{0}]" -F $e.ConnectedTo )
                }
                if ( $_.PrimaryIPAddress ) {
                    Validate-IPAddress ( $_.PrimaryIPAddress )
                }
            }

            if ( $e.ConfigureDefaultGateway ){
                assert -condition $e.GatewayIP -message "デフォルトゲートウェイのIPアドレスが設定されていません"
                assert -condition $e.GatewayMTU -message "デフォルトゲートウェイのMTUが設定されていません"
                assert -condition $e.AdminDistance -message "デフォルトゲートウェイの管理ディスタンスが設定されていません"
                Validate-IPAddress ( $e.GatewayIP )
            }

            if ( $e.StaticRoute.Network.Length -gt 0  ) {
                $e.StaticRoute | %{
                    Validate-CIDR ( $_.Network )
                    Validate-IPAddress ( $_.NextHop )
                }
            }

            if ( $e.Bridge -and $cl ) {
                $e.Bridge | %{
                    $pg = $cl | Get-VMHost | Get-VDSwitch | Get-VDPortgroup
                    assert_exists ( Get-NsxLogicalSwitch $_.LogicalSwitch ) ( "LogicalSwitch [{0}]" -F $_.LogicalSwitch )
                    assert_exists ( $pg ) ( "PortGroup [{0}]" -F $pg.Name )
                    $vlanId = $pg.VlanConfiguration.VlanId
                    assert -condition ( $vlanId -ne 0 ) -message "L2Brdigeに VLAN 0 のポートグループは接続できません"
                }
            }
        } catch {
            $error[0].Exception.ToString() | Write-Host -ForegroundColor Red
        }
    }
}
