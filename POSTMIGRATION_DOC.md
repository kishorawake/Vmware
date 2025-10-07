POSTMIGRATION and Mobility Group scripts
======================================

This document explains the two PowerShell scripts in this folder:

- `postmigration_check.ps1` — lightweight post-migration health checks (ping, RDP/SSH TCP port checks, gateway reachability). Resolves hostnames to IPv4 and writes results to CSV. Also writes an updated CSV with resolved IPv4 addresses.
- `mobilitygroup.ps1` — (HCX) Mobility Group migration helper. Creates mobility groups and kicks off migrations based on a CSV of VMs and migration options.

Both scripts read a CSV input file. The `postmigration_check.ps1` script is intended to be run after migration to verify connectivity.

POSTMIGRATION_CHECK.PS1
----------------------

What it does
- Reads the input CSV (must contain at least a `VMName` column). Optional columns: `IPAddress`, `Gateway`.
- If `IPAddress` is missing or empty, the script attempts DNS resolution of the `VMName` using `Resolve-Ip` and writes the resolved IPv4 back to the CSV output (a copy named `<original>_with_ips.csv`).
- For each resolved IP the script:
  - Performs an ICMP ping (uses `Test-Connection`) with configurable count.
  - Tests TCP port 3389 (RDP) and 22 (SSH) using a .NET `TcpClient` connect with a configurable timeout.
  - Determines gateway reachability. If the CSV provides a `Gateway` column that value is used. Otherwise, when run with `-AssumeGatewayDot1` the script will assume `.1` as the gateway in the VM's IPv4 subnet (for example, `10.0.1.42` -> `10.0.1.1`). It then pings the gateway.
- Outputs:
  - Human-friendly table to the console.
  - `postmigration_results.csv` (or the path supplied to `-OutputPath`) containing the check results per row.
  - `<originalfilename>_with_ips.csv` that contains the original CSV rows with an `IPAddress` column populated (if DNS resolution found an IPv4), allowing you to reuse a CSV with hostnames converted to IPs.

Usage
- On macOS/Linux use PowerShell Core (`pwsh`). On Windows use PowerShell.

Examples:

```powershell
# Basic run
pwsh ./postmigration_check.ps1 -CsvPath ".\Import_VM_list_mobility.csv"

# Assume .1 gateway and write results to custom file
pwsh ./postmigration_check.ps1 -CsvPath ".\Import_VM_list_mobility.csv" -AssumeGatewayDot1 -OutputPath ".\results_postmigration.csv"
```

Parameters
- `-CsvPath` (mandatory): Path to input CSV.
- `-OutputPath` (optional): Path to results CSV. Default: `./postmigration_results.csv`.
- `-PingCount` (optional): Number of ICMP echo requests. Default: `2`.
- `-TimeoutMs` (optional): Milliseconds to wait for TCP connect. Default: `3000`.
- `-AssumeGatewayDot1` (switch): If present and `Gateway` column isn't provided, assumes `.1` on the VM subnet as gateway.

CSV Requirements and example
- Required column: `VMName` (contains VM hostname/NetBIOS/DNS name)
- Optional columns:
  - `IPAddress` — IPv4 address, if present script will skip DNS resolution.
  - `Gateway` — explicit gateway to test for that VM.

Minimal example CSV (headers):

"VMName","OtherField","Gateway"
"vm-app-01.example.local","app","10.0.1.1"
"vm-db-01.example.local","db",""

Output CSV format (sample columns):
- `VMName`, `ResolvedIP`, `PingOK`, `RDP_3389_Open`, `SSH_22_Open`, `GatewayIP`, `GatewayPingOK`, `Notes`

Notes & Troubleshooting
- DNS resolution: `Resolve-Ip` uses .NET DNS APIs and returns the first IPv4 address found. If your hostnames are not resolvable, provide `IPAddress` in the CSV.
- ICMP on restricted networks: Some clouds or networks block ICMP. If pings always fail but TCP checks succeed, interpret results accordingly.
- TCP port check: The script performs a TCP connect to the port and treats a successful connect as "open". If the service accepts the connection then closes it, the test still reports success.
- Gateway heuristics: Only use `-AssumeGatewayDot1` if your environment uses `.1` as the gateway in each subnet.

MOBILITYGROUP.PS1
-----------------

What it does
- Reads an input CSV of VMs and migration options (columns described below).
- Performs validation of VMs and destination resources.
- Creates HCX mobility groups and individual VM migration entries and triggers the migration.
- Logs actions and outcomes to a log file.

CSV expectations (example column names)
- `MobilityGroupName`, `VM_NAME`, `MIGRATION_PROFILE`, `SCHEDULE`, `DESTINATION_VM_FOLDER`, `DESTINATION_CLUSTER_OR_HOST`, `DESTINATION_DATASTORE`, `DISK_TYPE`, `VMTOOLS`, `POWER_OFF`, `RETAIN_MAC`, ...

Usage
- The script requires HCX PowerShell modules and appropriate credentials.

Example:

```powershell
$cred = Get-Credential
.\mobilitygroup.ps1 -CsvPath ".\Import_VM_list_mobility.csv" -HcxManager "https://hcx.example.local" -HcxCredential $cred -DestSite "SITE-B" -LogPath ".\migration_log.txt"
```

Troubleshooting & recommendations
- Validate CSV headers before running the script. Add a `-WhatIf` or `-DryRun` mode if you want to preview actions before making changes.
- HCX cmdlets typically require Windows/PowerShell with the HCX plugin installed. If running from macOS PowerShell Core you may not have working HCX modules.

Maintenance and improvements
- Add a `-DryRun` flag to both scripts to show planned actions but not perform network calls.
- Add improved column validation and clearer error messages.
- Add parallel checks for `postmigration_check.ps1` to speed up large lists (using background jobs or Runspaces).

License
- These scripts are provided as-is. Adapt and test in a safe environment before running in production.

Contact
- For changes to these scripts, update them in this folder and maintain the CSV format used by your automation pipeline.
