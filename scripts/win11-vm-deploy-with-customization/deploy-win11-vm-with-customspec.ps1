<#
.SYNOPSIS
Deploys a Windows 11 VM from a template with BitLocker enabled by suspending BitLocker before Sysprep.

.DESCRIPTION
Author: 0xf4r
Version: 1.0
Date:    2025-08-13

This script:
1. Connects to vCenter.
2. Clones a Windows 11 template to a new VM.
3. Applies OS customization (vCenter spec or hardcoded values).
4. Suspends BitLocker inside the VM using VMware Tools + local admin credentials.
5. Powers on the VM to complete customization.

.REQUIREMENTS
- PowerShell 5.1 or later
- VMware PowerCLI 13.0 or later
- vCenter 7.x or later
- VMware Tools installed and running in template
- BitLocker enabled in template with TPM
- Local administrator credentials available

.CONDITIONS
- BitLocker protection will be suspended for 2 reboots before customization starts.
- Local admin credentials are stored in this script — protect this file.
#>

#region --- CONFIGURATION ---

# vCenter connection
$vcServer            = "vcenter.domain.local"

# Template / VM details
$templateName        = "W11-Template"
$vmName              = "DEV-W11-01"
$datacenterName      = "dc"
$folderPath          = "parentFolder/w11"        # Path inside Datacenter (slashes)
$clusterName         = "Cluster01"
$datastoreName       = "desktopssd"

# Customization
$useHardcodedSpec    = $false                    # $true = use hardcoded, $false = use vCenter spec
$customSpecName      = "profileq"                # Only used if $useHardcodedSpec = $false

# Hardcoded spec settings (only used if $useHardcodedSpec = $true)
$domainName          = "swt.co.uk"
$ouPath              = "OU=w11Desktops,DC=swt,DC=co,DC=uk"
$timeZone            = 85                        # UTC+0 (London)
$administratorPassword = "YourLocalAdminPass123!"
$ownerName           = "Your Owner Name"
$orgName             = "Your Organization"

# Local Admin account on the template VM
$localAdminUser      = "Administrator"
$localAdminPassword  = "YourLocalAdminPass123!"

#endregion

function Get-FolderByPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FolderPath,

        [Parameter(Mandatory = $true)]
        [VMware.VimAutomation.ViCore.Impl.V1.Inventory.DatacenterImpl]$RootContainer
    )

    $parts = $FolderPath.Trim('/').Split('/')
    $currentContainer = $RootContainer

    foreach ($part in $parts) {
        $nextFolder = Get-Folder -Name $part -Location $currentContainer -ErrorAction SilentlyContinue
        if (-not $nextFolder) {
            throw "Folder part '$part' not found under container '$($currentContainer.Name)'"
        }
        $currentContainer = $nextFolder
    }

    return $currentContainer
}

try {
    # --- Connect to vCenter ---
    Write-Host "Connecting to vCenter $vcServer ..." -ForegroundColor Cyan
    $cred = Get-Credential -Message "Enter vCenter credentials for $vcServer"
    Connect-VIServer -Server $vcServer -Credential $cred -ErrorAction Stop

    # --- Retrieve objects ---
    Write-Host "Retrieving vSphere objects..." -ForegroundColor Cyan
    $template   = Get-Template -Name $templateName -ErrorAction Stop
    $datacenter = Get-Datacenter -Name $datacenterName -ErrorAction Stop
    $folder     = Get-FolderByPath -FolderPath $folderPath -RootContainer $datacenter
    $cluster    = Get-Cluster -Name $clusterName -ErrorAction Stop
    $datastore  = Get-Datastore -Name $datastoreName -ErrorAction Stop

    if (-not $useHardcodedSpec) {
        $customSpec = Get-OSCustomizationSpec -Name $customSpecName -ErrorAction Stop
    }

    # --- Select compatible host ---
    $vmhost = Get-VMHost -Location $cluster |
        Where-Object { $_.ConnectionState -eq "Connected" } |
        Sort-Object CpuUsageMhz |
        Select-Object -First 1
    if (-not $vmhost) { throw "No compatible host found in cluster $clusterName." }

    # --- Prepare clone spec ---
    Write-Host "Preparing clone spec with TPM replacement..." -ForegroundColor Cyan
    $cloneSpec = New-Object VMware.Vim.VirtualMachineCloneSpec
    $cloneSpec.tpmProvisionPolicy = "replace"

    $relocateSpec = New-Object VMware.Vim.VirtualMachineRelocateSpec
    $relocateSpec.pool      = ($cluster | Get-ResourcePool).ExtensionData.MoRef
    $relocateSpec.datastore = $datastore.ExtensionData.MoRef
    $cloneSpec.location     = $relocateSpec

    # --- Clone VM ---
    Write-Host "Starting clone for VM '$vmName'..." -ForegroundColor Cyan
    $taskMoRef = $template.ExtensionData.CloneVM_Task($folder.ExtensionData.MoRef, $vmName, $cloneSpec)
    $task = Get-View $taskMoRef
    while ($task.Info.State -eq "running" -or $task.Info.State -eq "queued") {
        Start-Sleep -Seconds 5
        $task.UpdateViewData()
        Write-Host "Clone task is $($task.Info.State)..."
    }
    if ($task.Info.State -ne "success") { throw "VM clone failed: $($task.Info.Error.LocalizedMessage)" }
    Write-Host "Clone completed successfully." -ForegroundColor Green

    $newVM = Get-VM -Name $vmName -ErrorAction Stop

    # --- Apply customization ---
    if ($useHardcodedSpec) {
        Write-Host "Creating hardcoded customization spec..." -ForegroundColor Cyan
        $tempSpec = New-OSCustomizationSpec -Name "TempSpec-$vmName" -OSType Windows `
            -FullName $ownerName -OrgName $orgName -TimeZone $timeZone -ChangeSid `
            -Domain $domainName -DomainCredentials (Get-Credential -Message "Domain join account") `
            -JoinDomainOU $ouPath -AdminPassword (ConvertTo-SecureString $administratorPassword -AsPlainText -Force) `
            -Type NonPersistent -ErrorAction Stop
        Set-VM -VM $newVM -OSCustomizationSpec $tempSpec -Confirm:$false
    }
    else {
        Write-Host "Applying vCenter customization spec '$customSpecName'..." -ForegroundColor Cyan
        Set-VM -VM $newVM -OSCustomizationSpec $customSpec -Confirm:$false
    }

    # --- Suspend BitLocker via VMware Tools ---
    Write-Host "Suspending BitLocker protection inside VM before customization..." -ForegroundColor Cyan
    $guestCred = New-Object System.Management.Automation.PSCredential (
        $localAdminUser,
        (ConvertTo-SecureString $localAdminPassword -AsPlainText -Force)
    )
    Invoke-VMScript -VM $newVM -ScriptText "manage-bde -protectors -disable C: -RebootCount 2" `
        -GuestCredential $guestCred -ScriptType Powershell -ErrorAction Stop

    # --- Power on VM ---
    Write-Host "Powering on VM '$vmName'..." -ForegroundColor Cyan
    Start-VM -VM $newVM -Confirm:$false

    Write-Host "VM '$vmName' deployed, BitLocker suspended, customization will proceed." -ForegroundColor Green

} catch {
    Write-Error "Script failed: $_"
} finally {
    Disconnect-VIServer -Server $vcServer -Confirm:$false
}