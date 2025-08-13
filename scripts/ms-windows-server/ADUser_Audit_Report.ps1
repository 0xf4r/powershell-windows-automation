# ADUser_Audit_Report.ps1
# Purpose: Extract user account details from Active Directory for auditing unused accounts
# Author: 0xf4r
# Date: May 29, 2025

# Determine the script directory
if ($PSVersionTable.PSVersion.Major -ge 3) {
    $scriptDir = $PSScriptRoot
} else {
    $scriptDir = Split-Path $MyInvocation.MyCommand.Path
}

# Configurable parameters
$Domain = "DC=abc,DC=yourdomain,DC=com" # Modify to your domain, e.g., DC=yourdomain,DC=com
$OUPath = ""  # Leave empty for entire domain or set to OU, e.g., "OU=Users,DC=example,DC=com"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$DomainName = ($Domain -split ',' | ForEach-Object { $_ -replace '^DC=', '' }) -join '.'  # Extracts e.g., xyz.example.com
# Define subfolders and ensure they exist
$logsDir = Join-Path $scriptDir "Logs"
$reportsDir = Join-Path $scriptDir "Reports"
$null = New-Item -Path $logsDir -ItemType Directory -Force
$null = New-Item -Path $reportsDir -ItemType Directory -Force
$OutputCSV = Join-Path $reportsDir "$($DomainName)_ADUserAudit_$timestamp.csv"
$LogFile = Join-Path $logsDir "$($DomainName)_ADUserAudit_Log_$timestamp.txt"

# Simple log function
function Write-Log {
    param (
        [string]$Message
    )
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $Message"
    try {
        Add-Content -Path $LogFile -Value $logMessage -ErrorAction Stop
    } catch {
        Write-Host "Warning: Could not write to log: $LogFile - $_" -ForegroundColor Yellow
    }
    Write-Host $logMessage
}

# Initialize log file
$null = New-Item -Path $LogFile -ItemType File -Force
Write-Log "Starting AD user audit script"
Write-Log "Script directory: $scriptDir"

# Verify script directory is accessible
if (-not (Test-Path -Path $scriptDir -PathType Container)) {
    Write-Log "Error: Script directory ($scriptDir) is not accessible"
    Write-Host "Error: Script directory is not accessible." -ForegroundColor Red
    exit
}

# Import ActiveDirectory module
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Log "Active Directory module imported successfully"
}
catch {
    Write-Log "Error: Cannot load ActiveDirectory module. $_"
    Write-Host "Error: Cannot load ActiveDirectory module. Ensure it is installed." -ForegroundColor Red
    exit
}

try {
    # Set search base
    $SearchBase = if ($OUPath) { $OUPath } else { $Domain }
    Write-Log "Querying users from: $SearchBase"

    # Get AD users with comprehensive properties
    $Users = Get-ADUser -Filter * -SearchBase $SearchBase -Properties SamAccountName,DisplayName,LastLogonDate,WhenCreated,DistinguishedName,Description,Enabled,PasswordLastSet,UserPrincipalName,LockedOut,PasswordExpired,LastBadPasswordAttempt,AccountExpirationDate -ErrorAction Stop

    if (-not $Users) {
        Write-Log "No users found in: $SearchBase"
        Write-Host "No users found. Check your domain or OU path." -ForegroundColor Yellow
        exit
    }

    # Process users
    $UserData = $Users | ForEach-Object {
        # Handle attributes with null checks and logging
        $samAccountName = if ($null -ne $_.SamAccountName) { $_.SamAccountName } else { Write-Log "Warning: SamAccountName missing for DN: $($_.DistinguishedName)"; "" }
        $accountStatus = if ($null -ne $_.Enabled) { if ($_.Enabled) { "Enabled" } else { "Disabled" } } else { Write-Log "Warning: Enabled missing for user: $samAccountName"; "Unknown" }
        $whenCreated = if ($null -ne $_.WhenCreated) { $_.WhenCreated.ToString("yyyy-MM-dd HH:mm:ss") } else { Write-Log "Warning: WhenCreated missing for user: $samAccountName"; "" }
        $lastLogonDate = if ($null -ne $_.LastLogonDate) { $_.LastLogonDate.ToString("yyyy-MM-dd HH:mm:ss") } else { Write-Log "Warning: LastLogonDate missing for user: $samAccountName"; "" }
        $passwordLastSet = if ($null -ne $_.PasswordLastSet) { $_.PasswordLastSet.ToString("yyyy-MM-dd HH:mm:ss") } else { Write-Log "Warning: PasswordLastSet missing for user: $samAccountName"; "" }

        [PSCustomObject]@{
            SamAccountName        = $samAccountName
            DisplayName           = if ($null -ne $_.DisplayName) { $_.DisplayName } else { "" }
            UserPrincipalName     = if ($null -ne $_.UserPrincipalName) { $_.UserPrincipalName } else { "" }
            WhenCreated           = $whenCreated
            LastLogonDate         = $lastLogonDate
            PasswordLastSet       = $passwordLastSet
            AccountStatus         = $accountStatus
            OUPath                = if ($null -ne $_.DistinguishedName) { ($_.DistinguishedName -split ',',2)[1] } else { "Unknown OU" }
            Description           = if ($null -ne $_.Description) { $_.Description } else { "" }
            LockedOut             = if ($null -ne $_.LockedOut) { if ($_.LockedOut) { "Yes" } else { "No" } } else { "Unknown" }
            PasswordExpired       = if ($null -ne $_.PasswordExpired) { if ($_.PasswordExpired) { "Yes" } else { "No" } } else { "Unknown" }
            LastBadPasswordAttempt = if ($null -ne $_.LastBadPasswordAttempt) { $_.LastBadPasswordAttempt.ToString("yyyy-MM-dd HH:mm:ss") } else { "" }
            AccountExpirationDate = if ($null -ne $_.AccountExpirationDate) { $_.AccountExpirationDate.ToString("yyyy-MM-dd HH:mm:ss") } else { "" }
            InteractiveLogin      = ""  # No standard AD attribute for this
        }
    }

    # Export to CSV
    $UserCount = $UserData.Count
    Write-Log "Exporting $UserCount users to: $OutputCSV"
    $UserData | Export-Csv -Path $OutputCSV -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
    Write-Log "Successfully exported $UserCount users"
    Write-Host "Audit completed. $UserCount users exported to $OutputCSV"
    Write-Host "Log file: $LogFile"
}
catch {
    Write-Log "Error: $($_.Exception.Message)"
    Write-Host "Error occurred. Check log file: $LogFile" -ForegroundColor Red
    exit
}
finally {
    Write-Log "Script completed"
}