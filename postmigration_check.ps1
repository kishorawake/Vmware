# ...existing code...

param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [string]$OutputPath = ".\postmigration_results.csv",

    [int]$PingCount = 2,

    [int]$TimeoutMs = 3000,

    [switch]$AssumeGatewayDot1
)

function Resolve-Ip {
    param([string]$Name)
    try {
        $addrs = [System.Net.Dns]::GetHostAddresses($Name) 2>$null
        $ipv4 = $addrs | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1
        if ($ipv4) { return $ipv4.IPAddressToString }
    } catch {}
    return $null
}

if (-not (Test-Path $CsvPath)) {
    Write-Error "CSV not found: $CsvPath"
    exit 1
}
$rows = Import-Csv -Path $CsvPath

$results = foreach ($r in $rows) {
    $vmName = $r.VMName
    $ip = $null
    if ($r.PSObject.Properties.Match('IPAddress')) {
        $ip = if ($r.IPAddress -and $r.IPAddress.Trim()) { $r.IPAddress.Trim() } else { $null }
    }
    if (-not $ip) {
        $ip = Resolve-Ip -Name $vmName
    }

    # Inline ping check (no separate function)
    $pingOk = $false
    if ($ip) {
        try {
            $pingOk = Test-Connection -ComputerName $ip -Count $PingCount -Quiet -ErrorAction SilentlyContinue
        } catch {
            $pingOk = $false
        }
    }

    # Inline TCP port checks for RDP and SSH (no separate function)
    $rdpOk = $false
    $sshOk = $false
    if ($ip) {
        foreach ($portPair in @(@{Port=3389;Var='rdpOk'}, @{Port=22;Var='sshOk'})) {
            $tcp = New-Object System.Net.Sockets.TcpClient
            try {
                $ar = $tcp.BeginConnect($ip, $portPair.Port, $null, $null)
                if ($ar.AsyncWaitHandle.WaitOne($TimeoutMs)) {
                    $tcp.EndConnect($ar)
                    Set-Variable -Name $portPair.Var -Value $true -Scope 1
                } else {
                    Set-Variable -Name $portPair.Var -Value $false -Scope 1
                }
            } catch {
                Set-Variable -Name $portPair.Var -Value $false -Scope 1
            } finally {
                try { $tcp.Close() } catch {}
            }
        }
    }

    # Determine gateway: use CSV Gateway column if present, else optionally assume .1
    $gateway = $null
    if ($r.PSObject.Properties.Match('Gateway')) {
        $gateway = if ($r.Gateway -and $r.Gateway.Trim()) { $r.Gateway.Trim() } else { $null }
    }
    if (-not $gateway -and $AssumeGatewayDot1.IsPresent -and $ip) {
        $parts = $ip.Split('.')
        if ($parts.Count -eq 4) {
            $gateway = "$($parts[0]).$($parts[1]).$($parts[2]).1"
        }
    }

    $gatewayPing = $false
    if ($gateway) {
        try {
            $gatewayPing = Test-Connection -ComputerName $gateway -Count $PingCount -Quiet -ErrorAction SilentlyContinue
        } catch {
            $gatewayPing = $false
        }
    }

    [PSCustomObject]@{
        VMName        = $vmName
        ResolvedIP    = $ip
        PingOK        = $pingOk
        RDP_3389_Open = $rdpOk
        SSH_22_Open   = $sshOk
        GatewayIP     = $gateway
        GatewayPingOK = $gatewayPing
        Notes         = if (-not $ip) { "No IP resolved; provide IP in CSV or check DNS" } elseif (-not $pingOk) { "Ping failed" } else { "" }
    }
}

$results | Format-Table -AutoSize
try {
    $results | Export-Csv -Path $OutputPath -NoTypeInformation -Force
    Write-Host "Results exported to $OutputPath"
} catch {
    Write-Warning "Failed to export CSV: $_"
}

# ...existing code...