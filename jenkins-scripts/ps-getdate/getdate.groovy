pipeline {
    agent any
    
    parameters {
        string(name: 'TARGET_HOST', defaultValue: 'your-target-server', description: 'Target machine hostname or IP')
    }
    
    stages {
        stage('Execute PowerShell on Target Machine') {
            steps {
                script {
                    // Method 1: Execute PowerShell script directly on remote machine
                    powershell """
                        try {
                            Write-Host "Connecting to ${params.TARGET_HOST}..."
                            \$result = Invoke-Command -ComputerName "${params.TARGET_HOST}" -FilePath "get-date-script.ps1"
                            Write-Host "Remote execution successful:"
                            Write-Host \$result
                        }
                        catch {
                            Write-Error "Failed to execute on remote machine: \$_"
                            exit 1
                        }
                    """
                }
            }
        }
        
        stage('Alternative: Execute Inline Command') {
            steps {
                script {
                    // Method 2: Execute PowerShell commands directly without separate script file
                    powershell """
                        try {
                            Write-Host "Executing inline PowerShell on ${params.TARGET_HOST}..."
                            \$result = Invoke-Command -ComputerName "${params.TARGET_HOST}" -ScriptBlock {
                                # Your PowerShell commands here
                                Get-Date
                                Write-Host "Computer Name: \$env:COMPUTERNAME"
                                Write-Host "Current User: \$env:USERNAME"
                            }
                            Write-Host "Inline execution result:"
                            Write-Host \$result
                        }
                        catch {
                            Write-Error "Failed to execute inline command: \$_"
                            exit 1
                        }
                    """
                }
            }
        }
    }
    
    post {
        always {
            echo 'Pipeline execution completed'
        }
        success {
            echo 'PowerShell execution on target machine was successful'
        }
        failure {
            echo 'Pipeline failed. Check the logs for details.'
        }
    }
}
