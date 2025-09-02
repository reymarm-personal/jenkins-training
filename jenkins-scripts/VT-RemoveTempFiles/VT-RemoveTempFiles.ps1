# PowerShell Multi-Server Execution Framework
# Framework for executing PowerShell scripts across multiple servers

param(
    [Parameter(Mandatory = $true)]
    [string]$ServerListFile,
    
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath,
    
    [Parameter(Mandatory = $false)]
    [hashtable]$ScriptParameters = @{},
    
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\Logs\Framework",
    
    [Parameter(Mandatory = $false)]
    [int]$MaxConcurrency = 10,
    
    [Parameter(Mandatory = $false)]
    [string]$Environment = "PROD",
    
    [Parameter(Mandatory = $false)]
    [PSCredential]$Credential,
    
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf = $false
)

# Initialize framework logging
function Initialize-FrameworkLogging {
    param([string]$LogPath)
    
    if (!(Test-Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }
    
    $script:FrameworkLogFile = Join-Path $LogPath "Framework_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    return $script:FrameworkLogFile
}

# Framework logging function
function Write-FrameworkLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [FRAMEWORK] [$Level] $Message"
    
    # Write to console with colors
    switch ($Level) {
        "INFO"    { Write-Host $logMessage -ForegroundColor Cyan }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "ERROR"   { Write-Host $logMessage -ForegroundColor Red }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
    }
    
    # Write to log file
    Add-Content -Path $script:FrameworkLogFile -Value $logMessage -ErrorAction SilentlyContinue
}

# Function to read and validate server list
function Get-ServerList {
    param([string]$ServerListFile)
    
    try {
        if (!(Test-Path $ServerListFile)) {
            throw "Server list file not found: $ServerListFile"
        }
        
        $servers = Get-Content -Path $ServerListFile | 
                  Where-Object { $_ -match '\S' -and !$_.StartsWith('#') } |
                  ForEach-Object { $_.Trim() }
        
        if ($servers.Count -eq 0) {
            throw "No valid servers found in the server list file"
        }
        
        Write-FrameworkLog "Loaded $($servers.Count) servers from $ServerListFile" "SUCCESS"
        return $servers
        
    } catch {
        Write-FrameworkLog "Error reading server list: $($_.Exception.Message)" "ERROR"
        throw
    }
}

# Function to test server connectivity
function Test-ServerConnectivity {
    param(
        [string[]]$Servers,
        [PSCredential]$Credential
    )
    
    Write-FrameworkLog "Testing connectivity to $($Servers.Count) servers..." "INFO"
    
    $results = @{}
    
    $Servers | ForEach-Object -Parallel {
        $server = $_
        $cred = $using:Credential
        
        try {
            $testResult = Test-NetConnection -ComputerName $server -Port 5985 -WarningAction SilentlyContinue
            
            if ($testResult.TcpTestSucceeded) {
                # Test WinRM session
                $session = $null
                try {
                    if ($cred) {
                        $session = New-PSSession -ComputerName $server -Credential $cred -ErrorAction Stop
                    } else {
                        $session = New-PSSession -ComputerName $server -ErrorAction Stop
                    }
                    
                    $result = @{ Success = $true; Error = $null }
                    Remove-PSSession -Session $session -ErrorAction SilentlyContinue
                } catch {
                    $result = @{ Success = $false; Error = $_.Exception.Message }
                }
            } else {
                $result = @{ Success = $false; Error = "Port 5985 not reachable" }
            }
        } catch {
            $result = @{ Success = $false; Error = $_.Exception.Message }
        }
        
        return @{ Server = $server; Result = $result }
    } -ThrottleLimit $MaxConcurrency | ForEach-Object {
        $results[$_.Server] = $_.Result
        
        if ($_.Result.Success) {
            Write-FrameworkLog "✓ $($_.Server) - Connected" "SUCCESS"
        } else {
            Write-FrameworkLog "✗ $($_.Server) - Failed: $($_.Result.Error)" "ERROR"
        }
    }
    
    $successCount = ($results.Values | Where-Object { $_.Success }).Count
    $failCount = $results.Count - $successCount
    
    Write-FrameworkLog "Connectivity test completed: $successCount successful, $failCount failed" "INFO"
    
    return $results
}

# Function to execute script on servers
function Invoke-ScriptOnServers {
    param(
        [string[]]$Servers,
        [string]$ScriptPath,
        [hashtable]$ScriptParameters,
        [PSCredential]$Credential,
        [switch]$WhatIf
    )
    
    Write-FrameworkLog "Starting script execution on $($Servers.Count) servers..." "INFO"
    
    if ($WhatIf) {
        Write-FrameworkLog "WHATIF: Would execute script on servers" "INFO"
        return @{}
    }
    
    # Read script content
    if (!(Test-Path $ScriptPath)) {
        throw "Script file not found: $ScriptPath"
    }
    
    $scriptContent = Get-Content -Path $ScriptPath -Raw
    $results = @{}
    
    $Servers | ForEach-Object -Parallel {
        $server = $_
        $script = $using:scriptContent
        $params = $using:ScriptParameters
        $cred = $using:Credential
        $env = $using:Environment
        
        $result = @{
            Server = $server
            StartTime = Get-Date
            EndTime = $null
            Success = $false
            Output = ""
            Error = ""
            ExitCode = -1
        }
        
        try {
            # Create session
            $session = $null
            if ($cred) {
                $session = New-PSSession -ComputerName $server -Credential $cred -ErrorAction Stop
            } else {
                $session = New-PSSession -ComputerName $server -ErrorAction Stop
            }
            
            # Add environment parameter
            $params['Environment'] = $env
            
            # Execute script
            $scriptBlock = [ScriptBlock]::Create($script)
            $output = Invoke-Command -Session $session -ScriptBlock $scriptBlock -ArgumentList $params -ErrorAction Stop
            
            $result.Success = $true
            $result.Output = $output | Out-String
            $result.ExitCode = 0
            
            # Clean up session
            Remove-PSSession -Session $session -ErrorAction SilentlyContinue
            
        } catch {
            $result.Error = $_.Exception.Message
            $result.ExitCode = 1
            
            # Clean up session on error
            if ($session) {
                Remove-PSSession -Session $session -ErrorAction SilentlyContinue
            }
        } finally {
            $result.EndTime = Get-Date
            $result.Duration = ($result.EndTime - $result.StartTime).TotalSeconds
        }
        
        return $result
        
    } -ThrottleLimit $MaxConcurrency | ForEach-Object {
        $results[$_.Server] = $_
        
        if ($_.Success) {
            Write-FrameworkLog "✓ $($_.Server) - Completed in $([math]::Round($_.Duration, 2))s" "SUCCESS"
        } else {
            Write-FrameworkLog "✗ $($_.Server) - Failed: $($_.Error)" "ERROR"
        }
    }
    
    return $results
}

# Main execution
try {
    # Initialize logging
    $frameworkLogFile = Initialize-FrameworkLogging -LogPath $LogPath
    Write-FrameworkLog "=== PowerShell Execution Framework Started ===" "INFO"
    Write-FrameworkLog "Environment: $Environment" "INFO"
    Write-FrameworkLog "Script: $ScriptPath" "INFO"
    Write-FrameworkLog "Server List: $ServerListFile" "INFO"
    Write-FrameworkLog "Max Concurrency: $MaxConcurrency" "INFO"
    Write-FrameworkLog "WhatIf Mode: $WhatIf" "INFO"
    Write-FrameworkLog "Log File: $frameworkLogFile" "INFO"
    
    # Load server list
    $servers = Get-ServerList -ServerListFile $ServerListFile
    
    # Test connectivity
    $connectivityResults = Test-ServerConnectivity -Servers $servers -Credential $Credential
    $availableServers = $connectivityResults.Keys | Where-Object { $connectivityResults[$_].Success }
    
    if ($availableServers.Count -eq 0) {
        throw "No servers are available for script execution"
    }
    
    Write-FrameworkLog "Proceeding with $($availableServers.Count) available servers" "INFO"
    
    # Execute script on available servers
    $executionResults = Invoke-ScriptOnServers -Servers $availableServers -ScriptPath $ScriptPath -ScriptParameters $ScriptParameters -Credential $Credential -WhatIf:$WhatIf
    
    # Generate summary report
    $successCount = ($executionResults.Values | Where-Object { $_.Success }).Count
    $failCount = $executionResults.Count - $successCount
    
    $summary = @{
        Framework = @{
            StartTime = $frameworkLogFile | Split-Path -Leaf | Select-String -Pattern '\d{8}_\d{6}' | ForEach-Object { $_.Matches.Value }
            Environment = $Environment
            ScriptPath = $ScriptPath
            TotalServers = $servers.Count
            AvailableServers = $availableServers.Count
            SuccessfulExecutions = $successCount
            FailedExecutions = $failCount
            OverallSuccess = $failCount -eq 0
        }
        ConnectivityResults = $connectivityResults
        ExecutionResults = $executionResults
    }
    
    # Export summary
    $summaryFile = Join-Path $LogPath "ExecutionSummary_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $summary | ConvertTo-Json -Depth 4 | Out-File -FilePath $summaryFile -Encoding UTF8
    
    Write-FrameworkLog "=== Execution Summary ===" "SUCCESS"
    Write-FrameworkLog "Total servers: $($servers.Count)" "INFO"
    Write-FrameworkLog "Available servers: $($availableServers.Count)" "INFO"
    Write-FrameworkLog "Successful executions: $successCount" "SUCCESS"
    Write-FrameworkLog "Failed executions: $failCount" "$(if($failCount -gt 0){'ERROR'}else{'INFO'})"
    Write-FrameworkLog "Summary exported to: $summaryFile" "INFO"
    Write-FrameworkLog "=== Framework Execution Completed ===" "SUCCESS"
    
    # Exit with appropriate code
    if ($summary.Framework.OverallSuccess) {
        exit 0
    } else {
        exit 1
    }
    
} catch {
    Write-FrameworkLog "Critical framework error: $($_.Exception.Message)" "ERROR"
    exit 2
}
