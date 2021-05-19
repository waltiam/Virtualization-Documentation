# Original Author: Taylor Brown
# Updated Author: Shalin Mehta
# The following functions provide an example for how one could create a backup and a reference point of a VM in Hyper-V

function Convert-VmBackupCheckpoint
{
    Param(
      [Parameter(Mandatory=$True)]
      [Microsoft.Management.Infrastructure.CimInstance]$BackupCheckpoint = $null
    )

    # Retrieve an instance of the snapshot management service
    $Msvm_VirtualSystemSnapshotService = Get-CimInstance -Namespace root\virtualization\v2 -Class Msvm_VirtualSystemSnapshotService

    # Convert the snapshot to a reference point, this function returns a job object.
    $job = ($Msvm_VirtualSystemSnapshotService | Invoke-CimMethod -MethodName "ConvertToReferencePoint" -Arguments @{
        AffectedSnapshot = $BackupCheckpoint
    })

    # Wait for the job to complete.
    $job | Trace-CimMethodExecution | Out-Null

    # The new reference point object is related to the job, GetReleated
    # always returns an array in this case there is only one member
    $refPoint = ($job.Job | Get-CimAssociatedInstance -ResultClassName "Msvm_VirtualSystemReferencePoint" | % {$_})

    # Return the reference point object
    return $refPoint
}

function Export-VMBackupCheckpoint
{
    [CmdletBinding(DefaultParametersetname="vmname")]
    Param(
      [Parameter(Mandatory=$True, ParameterSetName="vmname")]
      [string]$VmName = [String]::Empty,
      [Parameter(Mandatory=$True, ParameterSetName="vmid")]
      [string]$VmId = [String]::Empty,

      [Parameter(Mandatory=$True)]
      [string]$DestinationPath = [String]::Empty,

      [Parameter(Mandatory=$True)]
      [Microsoft.Management.Infrastructure.CimInstance]$BackupCheckpoint = $null,

      [Microsoft.Management.Infrastructure.CimInstance]$ReferencePoint = $null,

      [bool]$noWait = $false
    )

    # Retrieve an instance of the virtual machine management service
    $Msvm_VirtualSystemManagementService = Get-CimInstance -Namespace root\virtualization\v2 -Class Msvm_VirtualSystemManagementService

    if ($PsCmdlet.ParameterSetName -eq "vmname"){
        $filter = "ElementName='$vmName'"
    } else {
        $filter = "Name='$VmId'"
    }
    # Retrieve an instance of the virtual machine computer system that will be snapshoted
    $Msvm_ComputerSystem = Get-CimInstance -Namespace root\virtualization\v2 -Class Msvm_ComputerSystem -Filter $filter

    # Retrieve an instance of the Export Setting Data Class (this is used to inform the export operation)
    # GetReleated always returns an array in this case there is only one member
    $Msvm_VirtualSystemExportSettingData = ($Msvm_ComputerSystem | Get-CimAssociatedInstance -ResultClassName "Msvm_VirtualSystemExportSettingData" -Association "Msvm_SystemExportSettingData" | % {$_})

    # Specify the export options
    # CopySnapshotConfiguration
    # 0: ExportAllSnapshots - All snapshots will be exported with the VM.
    # 1: ExportNoSnapshots - No snapshots will be exported with the VM.
    # 2: ExportOneSnapshot - The snapshot identified by the SnapshotVirtualSystem property will be exported with the VM.
    # 3: ExportOneSnapshotUseVmId - The snapshot identified by the SnapshotVirtualSystem property will be exported with the VM. Using the VMs ID.
    $Msvm_VirtualSystemExportSettingData.CopySnapshotConfiguration = 3

    # CopyVmRuntimeInformation
    # Indicates whether the VM runtime information will be copied when the VM is exported. (i.e. saved state)
    $Msvm_VirtualSystemExportSettingData.CopyVmRuntimeInformation = $false

    # CopyVmStorage
    # Indicates whether the VM storage will be copied when the VM is exported. (i.e. VHDs/VHDx files)
    $Msvm_VirtualSystemExportSettingData.CopyVmStorage = $true

    # CreateVmExportSubdirectory
    # Indicates whether a subdirectory with the name of the VM will be created when the VM is exported.
    $Msvm_VirtualSystemExportSettingData.CreateVmExportSubdirectory = $false

    # SnapshotVirtualSystem
    # Path to a Msvm_VirtualSystemSettingData instance that represents the snapshot to be exported with the VM.
    $Msvm_VirtualSystemExportSettingData.SnapshotVirtualSystem = (Get-CimInstancePath -CimInstance $BackupCheckpoint)

    # DifferentialBase
    # Base for differential export. This is either path to a Msvm_VirtualSystemReferencePoint instance that
    # represents the reference point or path to a Msvm_VirtualSystemSettingData instance that
    # represents the snapshot to be used as a base for differential export. If the CopySnapshotConfiguration
    # property is not set to 3(ExportOneSnapshotUseVmId), this property is ignored."
    if ($null -eq $ReferencePoint) {
        $Msvm_VirtualSystemExportSettingData.DifferentialBackupBase = $ReferencePoint
    }
    else {
        $Msvm_VirtualSystemExportSettingData.DifferentialBackupBase = (Get-CimInstancePath -CimInstance $ReferencePoint)
    }

    # StorageConfiguration
    # Indicates what should be the VHD path in the exported configuration.
    # 0: StorageConfigurationCurrent - The exported configuration would point to the current VHD.
    # 1: StorageConfigurationBaseVhd - The exported configuration would point to the base VHD.
    $Msvm_VirtualSystemExportSettingData.BackupIntent = 1

    #Export the virtual machine snapshot, this method returns a job object.
    $job = ($Msvm_VirtualSystemManagementService | Invoke-CimMethod -MethodName "ExportSystemDefinition" -Arguments @{
        ComputerSystem = $Msvm_ComputerSystem;
        ExportDirectory = $DestinationPath;
        ExportSettingData = ($Msvm_VirtualSystemExportSettingData | ConvertTo-CimEmbeddedString)
    })

    if (!$noWait)
    {
        $job | Trace-CimMethodExecution | Out-Null
    }
}

function Get-VmBackupCheckpoints
{
    [CmdletBinding(DefaultParametersetname="vmname")]
    Param(
      [Parameter(Mandatory=$True, ParameterSetName="vmid")]
      [string]$VmId = [String]::Empty,
      [Parameter(Mandatory=$True, ParameterSetName="vmname")]
      [string]$VmName = [String]::Empty
    )

    if ($PsCmdlet.ParameterSetName -eq "vmname"){
        $filter = "ElementName='$vmName'"
    } else {
        $filter = "Name='$VmId'"
    }

    # Retrieve an instance of the virtual machine computer system that contains recovery checkpoints
    $Msvm_ComputerSystem = Get-CimInstance -Namespace root\virtualization\v2 -Class Msvm_ComputerSystem -Filter $filter

    # Retrieve all snapshot associations for the virtual machine
    $allSnapshotAssociations = ($Msvm_ComputerSystem | Get-CimAssociatedInstance -ResultClassName "CIM_VirtualSystemSettingData" -Association "Msvm_SnapshotOfVirtualSystem" | % {$_})

    # Enumerate across all of the instances and add all recovery snapshots to an array
    $virtualSystemSnapshots = $allSnapshotAssociations | Where-Object { $_.VirtualSystemType -eq "Microsoft:Hyper-V:Snapshot:Recovery" }

    # Return the array of recovery snapshots
    return $virtualSystemSnapshots
}

function Get-VmReferencePoints
{
    [CmdletBinding(DefaultParametersetname="vmname")]
    Param(
      [Parameter(Mandatory=$True, ParameterSetName="vmid")]
      [string]$VmId = [String]::Empty,
      [Parameter(Mandatory=$True, ParameterSetName="vmname")]
      [string]$VmName = [String]::Empty
    )

    if ($PsCmdlet.ParameterSetName -eq "vmname"){
        $filter = "ElementName='$vmName'"
    } else {
        $filter = "Name='$VmId'"
    }

    # Retrieve an instance of the virtual machine computer system that contains reference points
    $Msvm_ComputerSystem = Get-CimInstance -Namespace root\virtualization\v2 -Class Msvm_ComputerSystem -Filter $filter

    # Retrieve all refrence associations of the virtual machine
    $allRefPoints = ($Msvm_ComputerSystem | Get-CimAssociatedInstance -ResultClassName "Msvm_VirtualSystemReferencePoint" -Association "Msvm_ReferencePointOfVirtualSystem" | % {$_})

    # Enumerate across all of the instances and add all recovery points to an array
    $virtualSystemRefPoints = $allRefPoints

    # Return the array of recovery points
    return $virtualSystemRefPoints
}

function New-VmBackupCheckpoint
{
    [CmdletBinding(DefaultParametersetname="vmname")]
    Param(
      [Parameter(Mandatory=$True, ParameterSetName="vmid")]
      [string]$VmId = [String]::Empty,
      [Parameter(Mandatory=$True, ParameterSetName="vmname")]
      [string]$VmName = [String]::Empty,

      [ValidateSet('ApplicationConsistent','CrashConsistent')]
      [string]$ConsistencyLevel = "ApplicationConsistent"
    )

    # Retrieve an instance of the virtual machine management service
    $Msvm_VirtualSystemManagementService = Get-CimInstance -Namespace root\virtualization\v2 -Class Msvm_VirtualSystemManagementService

    # Retrieve an instance of the virtual machine snapshot service
    $Msvm_VirtualSystemSnapshotService = Get-CimInstance -Namespace root\virtualization\v2 -Class Msvm_VirtualSystemSnapshotService

    if ($PsCmdlet.ParameterSetName -eq "vmname"){
        $filter = "ElementName='$vmName'"
    } else {
        $filter = "Name='$VmId'"
    }

    $consistencyLevelSetter = -1

    # Identify the consistency level for the snapshot.
    # 1: Application Consistent
    # 2: Crash Consistent
    switch ($ConsistencyLevel)
    {
        "ApplicationConsistent" {
            $consistencyLevelSetter = 1
        }

        "CrashConsistent" {
            $consistencyLevelSetter = 2
        }

        default {
        throw "Unexpected Consistency Level Specified"
        }
    }

    # Retrieve an instance of the virtual machine computer system that will be snapshotted
    $Msvm_ComputerSystem = Get-CimInstance -Namespace root\virtualization\v2 -Class Msvm_ComputerSystem -Filter $filter

    # Create an instance of the Msvm_VirtualSystemSnapshotSettingData, this class provides options on how the checkpoint will be created.
    $Msvm_VirtualSystemSnapshotSettingData = (Get-CimClass -Namespace "root\virtualization\v2" -ClassName "Msvm_VirtualSystemSnapshotSettingData" | New-CimInstance -ClientOnly -Property @{ConsistencyLevel = $consistencyLevelSetter; IgnoreNonSnapshottableDisks = $true})

    # Create the virtual machine snapshot, this method returns a job object.
    $job = ($Msvm_VirtualSystemSnapshotService | Invoke-CimMethod -MethodName "CreateSnapshot" -Arguments @{
        AffectedSystem = $Msvm_ComputerSystem;
        SnapshotSettings = ($Msvm_VirtualSystemSnapshotSettingData | ConvertTo-CimEmbeddedString);
        SnapshotType = 32768;
    })

    # Waits for the job to complete and processes any errors.
    $job | Trace-CimMethodExecution | Out-Null

    # Retrieves the snapshot object resulting from the snapshot.
    $snapshot = ($job.Job | Get-CimAssociatedInstance -ResultClassName "Msvm_VirtualSystemSettingData" | % {$_})

    # Returns the snapshot instance
    return $snapshot
}

function Remove-VmReferencePoint
{
    Param(
      [Parameter(Mandatory=$True)]
      [Microsoft.Management.Infrastructure.CimInstance]$ReferencePoint = $null
    )


    # Retrieve an instance of the virtual machine refrence point service
    $Msvm_VirtualSystemReferencePointService = Get-CimInstance -Namespace root\virtualization\v2 -Class Msvm_VirtualSystemReferencePointService

    # Removes the virtual machine reference, this method returns a job object.
    $job = ($Msvm_VirtualSystemReferencePointService | Invoke-CimMethod -MethodName "DestroyReferencePoint" -Arguments @{
        AffectedReferencePoint = $ReferencePoint
    })

    # Waits for the job to complete and processes any errors.
    $job | Trace-CimMethodExecution | Out-Null
}