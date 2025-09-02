# Enhanced Temp Files Cleanup Script
# Best Practices Applied: Error Handling, Logging, Progress Tracking, Parameterization

param(
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\Logs\TempCleanup",
    
    [Parameter(Mandatory = $false)]
    [int]$DaysOld = 7,
    
    [Parameter(Mandatory = $false)]
    [string]$Environment = "PROD",
    
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf = $false
)

# Initialize logging
function Initialize-Logging {
    param([string]$LogPath)
    
    if (!(Test-Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }
    
    $script:LogFile = Join-Path $LogPath "TempCleanup_$(Get-Date -Format 'yyyyMMdd_HHmmss')_$env:COMPUTERNAME.log"
    return $script:LogFile
}

# Enhanced logging function
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] [$env:COMPUTERNAME] $Message"
    
    # Write to console with colors
    switch ($Level) {
        "INFO"    { Write-Host $logMessage -ForegroundColor White }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "ERROR"   { Write-Host $logMessage -ForegroundColor Red }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
    }
    
    # Write to log file
    Add-Content -Path $script:LogFile -Value $logMessage -ErrorAction SilentlyContinue
}

# Function to get folder size
function Get-FolderSize {
    param([string]$Path)
    
    try {
        if (Test-Path $Path) {
            $size = (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue | 
                    Measure-Object -Property Length -Sum).Sum
            return [math]::Round($size / 1MB, 2)
        }
        return 0
    } catch {
        return 0
    }
}

# Enhanced cleanup function
function Remove-TempFiles {
    param(
        [string]$Path,
        [string]$Description,
        [int]$DaysOld,
        [switch]$WhatIf
    )
    
    try {
        if (!(Test-Path $Path)) {
            Write-Log "Path not found: $Path" "WARNING"
            return @{ Success = $false; SizeBefore = 0; SizeAfter = 0; FilesRemoved = 0 }
        }
        
        $sizeBefore = Get-FolderSize -Path $Path
        Write-Log "Processing $Description at: $Path" "INFO"
        Write-Log "Folder size before cleanup: $sizeBefore MB" "INFO"
        
        $cutoffDate = (Get-Date).AddDays(-$DaysOld)
        $filesToRemove = Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
                        Where-Object { !$_.PSIsContainer -and $_.LastWriteTime -lt $cutoffDate }
        
        $filesCount = ($filesToRemove | Measure-Object).Count
        
        if ($filesCount -eq 0) {
            Write-Log "No files older than $DaysOld days found in $Description" "INFO"
            return @{ Success = $true; SizeBefore = $sizeBefore; SizeAfter = $sizeBefore; FilesRemoved = 0 }
        }
        
        Write-Log "Found $filesCount files older than $DaysOld days" "INFO"
        
        if ($WhatIf) {
            Write-Log "WHATIF: Would remove $filesCount files from $Description" "INFO"
            return @{ Success = $true; SizeBefore = $sizeBefore; SizeAfter = $sizeBefore; FilesRemoved = $filesCount }
        }
        
        $removedCount = 0
        foreach ($file in $filesToRemove) {
            try {
                #Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                $removedCount++
            } catch {
                Write-Log "Failed to remove file: $($file.FullName) - $($_.Exception.Message)" "ERROR"
            }
        }
        
        # Remove empty directories
        try {
            Get-ChildItem -Path $Path -Recurse -Force -Directory -ErrorAction SilentlyContinue |
            Where-Object { (Get-ChildItem -Path $_.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0 } |
            #Remove-Item -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Log "Warning: Could not remove some empty directories - $($_.Exception.Message)" "WARNING"
        }
        
        $sizeAfter = Get-FolderSize -Path $Path
        $spaceSaved = $sizeBefore - $sizeAfter
        
        Write-Log "Cleanup completed for $Description" "SUCCESS"
        Write-Log "Files removed: $removedCount of $filesCount" "SUCCESS"
        Write-Log "Folder size after cleanup: $sizeAfter MB" "SUCCESS"
        Write-Log "Space saved: $spaceSaved MB" "SUCCESS"
        
        return @{ 
            Success = $true
            SizeBefore = $sizeBefore
            SizeAfter = $sizeAfter
            FilesRemoved = $removedCount
            SpaceSaved = $spaceSaved
        }
        
    } catch {
        Write-Log "Error processing $Description`: $($_.Exception.Message)" "ERROR"
        return @{ Success = $false; SizeBefore = 0; SizeAfter = 0; FilesRemoved = 0 }
    }
}

# Main execution
try {
    # Initialize logging
    $logFile = Initialize-Logging -LogPath $LogPath
    Write-Log "=== Temp Files Cleanup Started ===" "INFO"
    Write-Log "Environment: $Environment" "INFO"
    Write-Log "Server: $env:COMPUTERNAME" "INFO"
    Write-Log "Days Old Threshold: $DaysOld" "INFO"
    Write-Log "WhatIf Mode: $WhatIf" "INFO"
    Write-Log "Log File: $logFile" "INFO"
    
    # Define cleanup locations
    $cleanupLocations = @(
        @{ Path = "$env:TEMP"; Description = "User Temp Directory" },
        @{ Path = "$env:WINDIR\Temp"; Description = "Windows Temp Directory" },
        @{ Path = "$env:LOCALAPPDATA\Temp"; Description = "Local AppData Temp" },
        @{ Path = "$env:WINDIR\Prefetch"; Description = "Windows Prefetch" },
        @{ Path = "$env:WINDIR\SoftwareDistribution\Download"; Description = "Windows Update Cache" }
    )
    
    # Add IIS logs if IIS is installed
    if (Get-Service W3SVC -ErrorAction SilentlyContinue) {
        $cleanupLocations += @{ Path = "$env:SystemDrive\inetpub\logs\LogFiles"; Description = "IIS Log Files" }
    }
    
    $results = @()
    $totalSpaceSaved = 0
    $totalFilesRemoved = 0
    
    # Process each location
    foreach ($location in $cleanupLocations) {
        $result = Remove-TempFiles -Path $location.Path -Description $location.Description -DaysOld $DaysOld -WhatIf:$WhatIf
        $results += [PSCustomObject]@{
            Location = $location.Description
            Path = $location.Path
            Success = $result.Success
            SizeBefore = $result.SizeBefore
            SizeAfter = $result.SizeAfter
            FilesRemoved = $result.FilesRemoved
            SpaceSaved = $result.SpaceSaved
        }
        
        if ($result.Success) {
            $totalSpaceSaved += $result.SpaceSaved
            $totalFilesRemoved += $result.FilesRemoved
        }
    }
    
    # Summary
    Write-Log "=== Cleanup Summary ===" "SUCCESS"
    Write-Log "Total files removed: $totalFilesRemoved" "SUCCESS"
    Write-Log "Total space saved: $([math]::Round($totalSpaceSaved, 2)) MB" "SUCCESS"
    
    # Return results for Jenkins consumption
    $summaryObject = @{
        Server = $env:COMPUTERNAME
        Environment = $Environment
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        TotalFilesRemoved = $totalFilesRemoved
        TotalSpaceSaved = [math]::Round($totalSpaceSaved, 2)
        Results = $results
        LogFile = $logFile
        Success = ($results | Where-Object { !$_.Success }).Count -eq 0
    }
    
    # Export summary as JSON for Jenkins
    $summaryFile = Join-Path $LogPath "Summary_$(Get-Date -Format 'yyyyMMdd_HHmmss')_$env:COMPUTERNAME.json"
    $summaryObject | ConvertTo-Json -Depth 3 | Out-File -FilePath $summaryFile -Encoding UTF8
    
    Write-Log "Summary exported to: $summaryFile" "INFO"
    Write-Log "=== Temp Files Cleanup Completed ===" "SUCCESS"
    
    # Exit with appropriate code
    if ($summaryObject.Success) {
        exit 0
    } else {
        exit 1
    }
    
} catch {
    Write-Log "Critical error during cleanup: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack Trace: $($_.Exception.StackTrace)" "ERROR"
    exit 2
}
