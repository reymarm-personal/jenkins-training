pipeline {
    agent any

    stages {
        stage('Report') {
            steps {
                bat 'echo "this is a report" > report.txt'
                archiveArtifacts allowEmptyArchive: true,
                    artifacts: '*.txt',
                    fingerprint: true,
                    followSymlinks: false,
                    onlyIfSuccessful: true
            }
        }
    }
}