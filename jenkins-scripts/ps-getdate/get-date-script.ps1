# get-date-script.ps1
# Simple PowerShell script to demonstrate remote execution (no credentials required)

Write-Host "=== PowerShell Script Execution Started ===" -ForegroundColor Green

# Get current date and time
$currentDate = Get-Date
Write-Host "Current Date and Time: $currentDate" -ForegroundColor Yellow

# Get formatted date
$formattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "Formatted Date: $formattedDate" -ForegroundColor Cyan

# Get computer information
$computerName = $env:COMPUTERNAME
Write-Host "Computer Name: $computerName" -ForegroundColor Magenta

# Get current user
$currentUser = $env:USERNAME
Write-Host "Current User: $currentUser" -ForegroundColor Blue

# Additional system information
$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object Caption, Version
Write-Host "OS: $($osInfo.Caption) - Version: $($osInfo.Version)" -ForegroundColor White

# Show PowerShell version
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor DarkGreen

Write-Host "=== PowerShell Script Execution Completed ===" -ForegroundColor Green

# Return a success message
return "Script executed successfully on $computerName at $formattedDate"
