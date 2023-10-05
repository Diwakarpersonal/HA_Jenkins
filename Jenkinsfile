pipeline {
    agent any
    parameters {
        choice(name: 'Action', choices: ['Create infrastructure', 'Destroy infrastructure'], description: 'Select a choice')
    }
    environment {
        AWS_CREDENTIALS = credentials('aws')
        AWS_DEFAULT_REGION = 'ap-south-1'
    }
    stages {
        stage('Clone Terraform Repository') {
            when {
                expression { params.Action == 'Create infrastructure' }
            }
            steps {
                dir(path: 'terraform') {
                    git credentialsId: 'github', url: 'https://github.com/diwakar-opstree/HA_Jenkins.git'
                    sh """
                        terraform init
                        terraform plan -out=tfplan
                        terraform apply -input=false tfplan
                    """
                    script {
                        def publicip = sh(script: 'terraform output Public_instance_ip | xargs').trim()
                        def Jenkins_URL = sh(script: 'terraform output elb_dns_name').trim()
                        env.remote_host = publicip
                        env.Your_Jenkins_URL = Jenkins_URL
                    }
                    script {
                        printf "Your_Jenkins_URL: %s", env.Your_Jenkins_URL
                        printf "Your Bastion instance ip: %s", env.remote_host
                    }
                }
            }
        }
        stage('Print Choice 2') {
            when {
                expression { params.Action == 'Destroy infrastructure' }
            }
            steps {
                dir(path: 'terraform') {
                    sh 'chmod 777 private_key.pem'
                    sh 'terraform destroy -auto-approve'
                }
            }
        }
    }
}        