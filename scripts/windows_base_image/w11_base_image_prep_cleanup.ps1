<#
.SYNOPSIS
    Cleans a Windows 11 base image before creating VMs.

.DESCRIPTION
    Performs full cleanup including temporary files, logs, disk cleanup, registry keys,
    sysprep file removal, IPv6 disable, services disable, cleaning directories, and offers shutdown prompt.

.NOTES
    Author  : 0xf4r
    Date    : 2025-07-25
    Run As  : Administrator (Required)
#>

Set-ExecutionPolicy RemoteSigned -Scope CurrentUser #Digitally sign the script for current user

# Check for Administrator privileges and restart with elevation if needed
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltinRole] "Administrator")) {
    Write-Host "Script is not running as Administrator. Restarting with elevated privileges..." -ForegroundColor Yellow
    
    # Relaunch the script with elevated rights
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $psi.Verb = "runas"  # This triggers the UAC elevation prompt
    try {
        [System.Diagnostics.Process]::Start($psi) | Out-Null
    }
    catch {
        Write-Error "Failed to restart script as Administrator: $_"
    }
    exit
}

# ========================
# Configuration Header
# ========================
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Windows 11 Base Image Cleanup Script" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Initialize status tracking variable
$CleanupStatus = @()

# ========================
# Step 1 - Clear Temporary Files
# ========================
Write-Host "[1/10] Deleting temporary files..." -ForegroundColor White

try {
    Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    $CleanupStatus += "Temporary files deleted"
}
catch {
    Write-Warning "Failed to delete temp files: $_"
}

# ========================
# Step 2 - Clear Windows Event Logs
# ========================
Write-Host "[2/10] Clearing Windows Event Logs..." -ForegroundColor White

$logsToClear = @(
    "Application",
    "System",
    "Security",
    "Setup",
    "ForwardedEvents",
    "Microsoft-Windows-Diagnostics-Performance/Operational",
    "Windows Live ID/Operational"
)

foreach ($log in $logsToClear) {
    try {
        Clear-EventLog -LogName $log -ErrorAction Stop
        Write-Host "- Cleared $log log." -ForegroundColor Gray
        $CleanupStatus += "$log log cleared"
    }
    catch {
        Write-Warning "Failed to clear $log log: $_"
        $CleanupStatus += "$log log could not be cleared"
    }
}

# ========================
# Step 3 - Full Disk Cleanup (System + DISM + Temp + User + Update)
# ========================
Write-Host "[3/10] Running full system disk cleanup..." -ForegroundColor White

try {
    # DISM: Clean up WinSxS and reset base image
    Write-Host "- Starting DISM component cleanup..."
    Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase | Out-Null

    # Clear Windows Update cache
    Write-Host "- Clearing Windows Update cache..."
    Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    Stop-Service -Name bits -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\Windows\SoftwareDistribution\*" -Recurse -Force -ErrorAction SilentlyContinue
    Start-Service -Name wuauserv -ErrorAction SilentlyContinue
    Start-Service -Name bits -ErrorAction SilentlyContinue

    # Clear Delivery Optimization cache
    Write-Host "- Clearing Delivery Optimization cache..."
    Remove-Item -Path "C:\ProgramData\Microsoft\Network\Downloader\*" -Recurse -Force -ErrorAction SilentlyContinue


    # Empty Recycle Bin Silently
    Write-Host "- Emptying Recycle Bin..."
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    
    <# Empty Recycle Bin for all users
    Write-Host "- Emptying Recycle Bin..."
    $Shell = New-Object -ComObject Shell.Application
    $Shell.Namespace(0xA).Items() | ForEach-Object { $_.InvokeVerb("delete") }
    #>

    # Remove thumbnail cache and UI temp data
    Write-Host "- Cleaning UI caches (thumbnail, explorer)..."
    Get-ChildItem "C:\Users\*\AppData\Local\Microsoft\Windows\Explorer\thumbcache*" -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

    # Clear Temp folders again to catch any remaining files
    Write-Host "- Removing remaining temp files..."
    Remove-Item -Path "C:\Windows\Temp\*", "$env:TEMP\*", "C:\Users\*\AppData\Local\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

    $CleanupStatus += "Full disk cleanup completed (DISM + Cache + Temp + Update)"
}
catch {
    Write-Warning "Disk cleanup failed: $_"
    $CleanupStatus += "Disk cleanup step encountered errors"
}

# ========================
# Step 4 - Remove Sysprep and Setup Files
# ========================
Write-Host "[4/10] Removing Sysprep and setup traces..." -ForegroundColor White

try {
    Remove-Item -Path "C:\Windows\System32\Sysprep\unattend.xml" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\Windows\System32\Sysprep\Panther\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\Windows\Panther\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\Sysprep\*" -Recurse -Force -ErrorAction SilentlyContinue
    $CleanupStatus += "Sysprep and setup files removed"
}
catch {
    Write-Warning "Failed to clean sysprep files: $_"
}

# ========================
# Step 5 - Remove Prefetch, Logs, and Crash Dumps
# ========================
Write-Host "[5/10] Cleaning logs, prefetch, CBS, and crash data..." -ForegroundColor White

try {
    Remove-Item -Path "C:\Windows\Prefetch\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\Windows\Logs\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\Windows\Logs\CBS\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\Windows\WinSxS\pending.xml" -Force -ErrorAction SilentlyContinue
    $CleanupStatus += "Log and crash files removed"
}
catch {
    Write-Warning "Failed to clean logs/prefetch: $_"
}

# ========================
# Step 6 - Stop Services
# ========================
Write-Host "[6/10] Stopping Services..." -ForegroundColor White

$servicesToStop = @(
    "bits",            # BITS service
    "wuauserv"         # Windows Update Service
)

foreach ($svc in $servicesToStop) {
    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
}

Set-Service -Name wuauserv -StartupType Disabled

Unregister-ScheduledTask -TaskName "Scheduled Start" -TaskPath "\Microsoft\Windows\WindowsUpdate\" -Confirm:$false

# ========================
# Step 7 - Disable IPv6
# ========================
Write-Host "[7/10] Disabling IPv6 Component..." -ForegroundColor White

REG ADD HKLM\System\CurrentControlSet\Services\Tcpip6\Parameters /v DisabledComponents /t REG_DWORD /d 0xff /f

# ========================
# Step 8 - Clean AV Directories
# ========================
Write-Host "[8/10] Deleting AV Directories..." -ForegroundColor White

# Take ownership recursively (silent)
Start-Process takeown.exe -ArgumentList '/f "C:\Program Files\AV\AV Agent\components\AV_agent\common\cache" /r /d y' -Wait -WindowStyle Hidden
Start-Process takeown.exe -ArgumentList '/f "C:\Program Files\AV\AV Agent\components\AV_agent\common\config" /r /d y' -Wait -WindowStyle Hidden
Start-Process takeown.exe -ArgumentList '/f "C:\Program Files\AV\AV Agent\components\AV_agent\common\snapshots" /r /d y' -Wait -WindowStyle Hidden
Start-Process takeown.exe -ArgumentList '/f "C:\ProgramData\AV\AV Agent" /r /d y' -Wait -WindowStyle Hidden

# Remove folders
Remove-Item -Path "C:\Program Files\AV\AV Agent\components\AV_agent\common\cache" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Program Files\AV\AV Agent\components\AV_agent\common\config" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Program Files\AV\AV Agent\components\AV_agent\common\snapshots" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\ProgramData\AV\AV Agent" -Recurse -Force -ErrorAction SilentlyContinue

# ========================
# Step 9 - Release Current IP Address
# ========================
Write-Host "[9/10] Releasing current DHCP assigned IP address..." -ForegroundColor White
# Uncomment the following line if you want to release IP address during cleanup
# ipconfig /release


# ========================
# Step 10 - Set Execution Policy Unrestrcted
# ========================
Write-Host "[10/10] Set Execution Policy Unrestricted for Current User..." -ForegroundColor White
Set-ExecutionPolicy Unrestricted -Scope CurrentUser -Force # This is done so new scripts can be executed by the user on new VM


# ========================
# Final Summary Report
# ========================
Write-Host "==========================================" -ForegroundColor Green
Write-Host "  Base Image Cleanup Successful" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""

# ========================
# Shutdown Prompt
# ========================
do {
    $confirm = Read-Host "Do you want to shutdown the system now? (Y/N)"
} while ($confirm -notmatch '^[YyNn]$')

if ($confirm -match '^[Yy]$') {
    Write-Host "Shutting down system in 5 seconds..." -ForegroundColor Cyan
    Start-Sleep -Seconds 5
    Stop-Computer -Force
}
else {
    Write-Host "Shutdown cancelled. You may close this window." -ForegroundColor Yellow
}
