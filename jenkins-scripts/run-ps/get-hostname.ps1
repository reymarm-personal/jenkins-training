# Simple PowerShell script to get hostname
# File: jenkins-scripts/run-ps/get-hostname.ps1

Write-Host "=== Remote Server Information ===" -ForegroundColor Green
Write-Host "Server Hostname: $(hostname)" -ForegroundColor Yellow
Write-Host "Current User: $($env:USERNAME)" -ForegroundColor Yellow
Write-Host "Current Date/Time: $(Get-Date)" -ForegroundColor Yellow
Write-Host "=================================" -ForegroundColor Green
