Write-Host "=============================================================" -ForegroundColor Yellow
Write-Host "CAUTION: This script applies a Microsoft-provided product key." -ForegroundColor Yellow
Write-Host "Ensure you have the proper licensing rights for your environment." -ForegroundColor Yellow
Write-Host "=============================================================" -ForegroundColor Yellow
Start-Sleep -Seconds 2

Set-Service -Name "LicenseManager" -StartupType Automatic
Start-Service -Name "LicenseManager"

Set-Service -Name "wuauserv" -StartupType Automatic
Start-Service -Name "wuauserv"

changepk.exe /productkey VK7JG-NPHTM-C97JM-9MPGT-3V66T

exit