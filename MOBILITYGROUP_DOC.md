mobilitygroup.ps1 — HCX Mobility Group migration helper
======================================================

This document explains usage, parameters, CSV format and behavior for `mobilitygroup.ps1` in this folder.

Summary
-------
`mobilitygroup.ps1` is an HCX migration helper script that:

- Reads a CSV of VMs and migration options.
- Validates source VM state and destination resources.
- Creates HCX Mobility Groups and per-VM HCX migration entries.
- Supports dynamic NIC mapping by inspecting VM network adapters and creating HCX network mappings.
- Starts Mobility Group migrations and logs results to a log file.

Prerequisites
-------------
- PowerShell with VMware PowerCLI and HCX PowerShell modules installed and loaded in the session.
- Network connectivity to vCenter(s) and HCX Manager.
- Credentials with sufficient privileges to create migrations and mobility groups in HCX.
- The CSV must be accessible from the machine running the script.

Parameters
----------
- `-CsvPath` (optional): Path to the CSV file containing VM migration rows. Default in the script is a placeholder `C:\path\to\Import_VM_list_mobility.csv` — supply a real path.
- `-HcxManager` (optional): HCX Manager URL. Default in script is placeholder `<HCX-Manager-URL>`.
- `-HcxCredential` (required): PSCredential used to authenticate to the HCX Manager. Create via `Get-Credential`.
- `-DestSite` (optional): Destination HCX site name. Default is placeholder `<DEST SITE>`.
- `-LogPath` (optional): Path to append script logs. Default is `C:\path\to\hcx_migration_log.txt` in the script.

How it works (high level)
-------------------------
1. Connects to the HCX server using `Connect-HCXServer -Server $HcxManager -Credential $HcxCredential`.
2. Resolves the source and destination HCX sites via `Get-HCXSite`.
3. Imports the CSV and groups rows by `MobilityGroupName`.
4. For each group, creates a Mobility Group configuration and iterates VMs in that group:
   - Validates VM power state and the requested `MIGRATION_PROFILE`.
   - Validates required destination resources exist (`DESTINATION_VM_FOLDER`, `DESTINATION_CLUSTER_OR_HOST`, `DESTINATION_DATASTORE`).
   - Builds network mappings by inspecting each VM's network adapters and using `Get-HCXNetwork` (adjust mapping logic if your NSX-T/segment names differ).
   - Builds migration options from CSV columns (disk type, tools upgrade, remove ISOs, retain MAC, upgrade HW, remove snapshots, custom attributes).
   - Creates a `New-HCXMigration` object for the VM. If scheduling is enabled in the CSV row, the script will add `-ScheduleStartTime` and `-ScheduleEndTime` (default example uses +12 to +15 days from now in the script; change as needed).
   - Adds the migration to the Mobility Group. The first VM creates the mobility group; subsequent VMs are appended.
5. Starts the Mobility Group migration with `Start-HCXMobilityGroupMigration`.
6. Logs added/skipped VMs and group summary lines to the log file using `Add-Content`.

CSV format (expected columns)
-----------------------------
The script expects a CSV where each row contains at least the following columns (case-insensitive):

- `MobilityGroupName` — Logical Mobility Group label.
- `VM_NAME` — VM name as known to vCenter/PowerCLI.
- `MIGRATION_PROFILE` — e.g., `Cold`, `vMotion`, `Bulk` (values your HCX expects).
- `SCHEDULE` — `True`/`False`; when `True` the script adds schedule start/end times to the migration entry.
- `DESTINATION_VM_FOLDER` — Destination VM folder path on the destination site.
- `DESTINATION_CLUSTER_OR_HOST` — Destination compute container (cluster or host) name.
- `DESTINATION_DATASTORE` — Destination datastore name.
- `DISK_TYPE` — Disk provisioning type (Thin/Thick) to use on destination.
- `VMTOOLS` — `True`/`False` to upgrade VMware Tools.
- `ISOS` — `True`/`False` to remove mounted ISOs before migration.
- `POWER_OFF` — `True`/`False` to force a power-off when needed.
- `RETAIN_MAC` — `True`/`False` to retain MAC addresses.
- `UPGRADE_HW` — `True`/`False` to upgrade hardware version on target.
- `REMOVE_SNAPS` — `True`/`False` to remove snapshots before migration.
- `CUSTOM_ATTRIB` — `True`/`False` to migrate custom attributes.

Rows may contain additional columns if your workflow requires them.

Example CSV (single row):

"MobilityGroupName","VM_NAME","MIGRATION_PROFILE","SCHEDULE","DESTINATION_VM_FOLDER","DESTINATION_CLUSTER_OR_HOST","DESTINATION_DATASTORE","DISK_TYPE","VMTOOLS","ISOS","POWER_OFF","RETAIN_MAC","UPGRADE_HW","REMOVE_SNAPS","CUSTOM_ATTRIB"
"MG-APP-01","vm-app-01","vMotion","False","/Datacenter/VMs/Apps","Cluster-A","Datastore1","Thin","True","True","False","False","False","True","False"

Logging
-------
- The script appends messages to the file path provided by `-LogPath` using `Add-Content`.
- Each VM processed generates `ADDED` or `SKIP` log lines. After each group, the script logs summary counts.

Notes, caveats and tips
----------------------
- Adjust network mapping logic inside `New-NetworkMapping` if your source and destination network naming conventions differ. The example attempts a direct name match; you may need substring matches or regular expressions for NSX-T segment names.
- The schedule start/end times in the script default to 12–15 days from now as an example. Change these values to meet your operational window or read schedule times from the CSV.
- The script uses `Get-HCXVM`, `New-HCXMigration`, `New-HCXMobilityGroup`, `Set-HCXMobilityGroup`, and `Start-HCXMobilityGroupMigration` — ensure HCX PowerShell modules support these cmdlets on your platform.
- Consider adding a `-DryRun` switch to validate CSV rows and print planned actions without creating HCX objects.
- Add parallelism if you need to speed up large imports; be careful with API rate-limits and vCenter/HCX concurrency limits.

Troubleshooting
---------------
- "Missing target resources" log lines indicate the destination folder/compute/datastore could not be resolved on the target site. Validate the CSV values match destination site names exactly or improve resolution logic.
- If network mapping cannot find destination networks, adjust `New-NetworkMapping` to use partial matches or a mapping table between source and destination network names.
- If HCX cmdlets fail with authentication or connectivity errors, validate `HcxManager` URL and `HcxCredential`, and that the HCX Manager is reachable.

Suggested improvements
----------------------
- Add CSV column validation at script start to fail fast with clear messages.
- Add a `-DryRun`/`-WhatIf` mode to preview actions.
- Make schedule start/end times configurable in the CSV or as script parameters.
- Add retries for transient HCX API failures and more robust error handling around cmdlet calls.

Example run
-----------
```powershell
$cred = Get-Credential
pwsh ./mobilitygroup.ps1 -CsvPath ".\Import_VM_list_mobility.csv" -HcxManager "https://hcx.example.local" -HcxCredential $cred -DestSite "SITE-B" -LogPath ".\hcx_migration_log.txt"
```

Contact and maintenance
-----------------------
- Update this doc when you change CSV column names or script behavior. Keep `MOBILITYGROUP_DOC.md` in the same folder as `mobilitygroup.ps1` for easy reference.
