# HCX Migration with Mobility Groups - Improved Script kishor
# Supports multiple Mobility Groups, dynamic NIC mapping, data validation, and flexible migration options from CSV

param(
    [string]$CsvPath = "C:\path\to\Import_VM_list_mobility.csv",
    [string]$HcxManager = "<HCX-Manager-URL>",
    [Parameter(Mandatory=$true)]
    [PSCredential]$HcxCredential,
    [string]$DestSite = "<DEST SITE>",
    [string]$LogPath = "C:\path\to\hcx_migration_log.txt"
)

function New-NetworkMapping {
    param (
        [string]$VMName,
        $SrcSite,
        $DstSite
    )
    $vm = Get-VM -Name $VMName
    $adapters = Get-NetworkAdapter -VM $vm
    $mappings = @()
    foreach ($adapter in $adapters) {
        $srcNetwork = Get-HCXNetwork -Name $adapter.NetworkName -Site $SrcSite
        # Logic to determine target network; adjust as needed for your environment
        $dstNetwork = Get-HCXNetwork -Name $adapter.NetworkName -Site $DstSite
        if ($srcNetwork -and $dstNetwork) {
            $mappings += New-HCXNetworkMapping -SourceNetwork $srcNetwork -DestinationNetwork $dstNetwork
        }
    }
    return $mappings
}

function Log-Result {
    param (
        [string]$Message
    )
    Add-Content -Path $LogPath -Value $Message
}

# Connect to HCX
Connect-HCXServer -Server $HcxManager -Credential $HcxCredential

# Get Source and Destination Sites
$HcxSrcSite = Get-HCXSite -Source
$HcxDstSite = Get-HCXSite -Destination $DestSite

# Import CSV details for the VMs to be migrated
$HCXVMS = Import-CSV $CsvPath

# Group VMs by MobilityGroupName
$groups = $HCXVMS | Group-Object -Property MobilityGroupName

foreach ($group in $groups) {
    $MobilityGroupName = $group.Name
    $NewMGC = New-HCXMobilityGroupConfiguration -SourceSite $HcxSrcSite -DestinationSite $HcxDstSite
    $first = $true
    $addedVMs = 0
    $skippedVMs = 0
    foreach ($HCXVM in $group.Group) {
        # Data validation
        $VMState = Get-VM -Name $HCXVM.VM_NAME | Select-Object -ExpandProperty PowerState
        $MigrationProfile = $HCXVM.MIGRATION_PROFILE
        $EnableSchedule = $HCXVM.SCHEDULE -eq "True"
        if ($EnableSchedule -and ($MigrationProfile -eq "Cold" -or $MigrationProfile -eq "vMotion")) {
            Log-Result "SKIP: $($HCXVM.VM_NAME) - Cannot schedule Cold/vMotion migrations."
            $skippedVMs++
            continue
        }
        if ($VMState -eq "PoweredOff" -and ($MigrationProfile -ne "Cold")) {
            Log-Result "SKIP: $($HCXVM.VM_NAME) - Powered off, not Cold migration."
            $skippedVMs++
            continue
        }
        if ($VMState -eq "PoweredOn" -and ($MigrationProfile -eq "Cold")) {
            Log-Result "SKIP: $($HCXVM.VM_NAME) - Powered on, Cold migration."
            $skippedVMs++
            continue
        }
        # Validate target resources
        $DstFolder = Get-HCXContainer $HCXVM.DESTINATION_VM_FOLDER -Site $HcxDstSite
        $DstCompute = Get-HCXContainer $HCXVM.DESTINATION_CLUSTER_OR_HOST -Site $HcxDstSite
        $DstDatastore = Get-HCXDatastore $HCXVM.DESTINATION_DATASTORE -Site $HcxDstSite
        if (-not $DstFolder -or -not $DstCompute -or -not $DstDatastore) {
            Log-Result "SKIP: $($HCXVM.VM_NAME) - Missing target resources."
            $skippedVMs++
            continue
        }
        # Dynamic NIC mapping
        $NetworkMapping = New-NetworkMapping -VMName $HCXVM.VM_NAME -SrcSite $HcxSrcSite -DstSite $HcxDstSite
        # Migration options from CSV
        $DiskType = $HCXVM.DISK_TYPE
        $VMToolsUpgrade = $HCXVM.VMTOOLS -eq "True"
        $RemoveISOs = $HCXVM.ISOS -eq "True"
        $PowerOff = $HCXVM.POWER_OFF -eq "True"
        $RetainMac = $HCXVM.RETAIN_MAC -eq "True"
        $UpgradeHW = $HCXVM.UPGRADE_HW -eq "True"
        $RemoveSnaps = $HCXVM.REMOVE_SNAPS -eq "True"
        $CustomAttrib = $HCXVM.CUSTOM_ATTRIB -eq "True"
        # Scheduling
        $startTime = [DateTime]::Now.AddDays(12)
        $endTime = [DateTime]::Now.AddDays(15)
        if ($EnableSchedule) {
            $NewMigration = New-HCXMigration -VM (Get-HCXVM $HCXVM.VM_NAME) `
                -MigrationType $MigrationProfile `
                -SourceSite $HcxSrcSite `
                -DestinationSite $HcxDstSite `
                -Folder $DstFolder `
                -TargetComputeContainer $DstCompute `
                -TargetDatastore $DstDatastore `
                -NetworkMapping $NetworkMapping `
                -DiskProvisionType $DiskType `
                -UpgradeVMTools $VMToolsUpgrade `
                -RemoveISOs $RemoveISOs `
                -ForcePowerOffVm $PowerOff `
                -MigrateCustomAttributes $CustomAttrib `
                -RetainMac $RetainMac `
                -UpgradeHardware $UpgradeHW `
                -RemoveSnapshots $RemoveSnaps `
                -ScheduleStartTime $startTime `
                -ScheduleEndTime $endTime `
                -MobilityGroupMigration
        } else {
            $NewMigration = New-HCXMigration -VM (Get-HCXVM $HCXVM.VM_NAME) `
                -MigrationType $MigrationProfile `
                -SourceSite $HcxSrcSite `
                -DestinationSite $HcxDstSite `
                -Folder $DstFolder `
                -TargetComputeContainer $DstCompute `
                -TargetDatastore $DstDatastore `
                -NetworkMapping $NetworkMapping `
                -DiskProvisionType $DiskType `
                -UpgradeVMTools $VMToolsUpgrade `
                -RemoveISOs $RemoveISOs `
                -ForcePowerOffVm $PowerOff `
                -MigrateCustomAttributes $CustomAttrib `
                -RetainMac $RetainMac `
                -UpgradeHardware $UpgradeHW `
                -RemoveSnapshots $RemoveSnaps `
                -MobilityGroupMigration
        }
        if ($first) {
            # Create the Mobility Group (first VM)
            New-HCXMobilityGroup -Name $MobilityGroupName -Migration $NewMigration -GroupConfiguration $NewMGC -ErrorAction SilentlyContinue
            $first = $false
        } else {
            # Add subsequent VMs to the Mobility Group
            Set-HCXMobilityGroup -MobilityGroup (Get-HCXMobilityGroup -Name $MobilityGroupName) -Migration $NewMigration -addMigration -ErrorAction SilentlyContinue
        }
        Log-Result "ADDED: $($HCXVM.VM_NAME) to $MobilityGroupName"
        $addedVMs++
    }
    # Start the migration for the Mobility Group
    Start-HCXMobilityGroupMigration -MobilityGroup (Get-HCXMobilityGroup -Name $MobilityGroupName) -ErrorAction SilentlyContinue
    Log-Result "Mobility Group ${MobilityGroupName}: ${addedVMs} VMs added, ${skippedVMs} VMs skipped."
}

# Disconnect from HCX
Disconnect-HCXServer