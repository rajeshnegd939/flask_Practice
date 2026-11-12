// flask_Practice CI/CD: Build -> Test -> Deploy to staging
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timeout(time: 30, unit: 'MINUTES')
    }

    environment {
        AWS_REGION     = 'ap-south-1'
        AWS_ACCOUNT_ID = '099739121791'
        DEPLOY_BUCKET  = "flask-deploy-${AWS_ACCOUNT_ID}"
        STAGING_NAME   = 'flask-staging'
        SNS_TOPIC_ARN  = "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:flask-ci-notifications"
        // tests use a throwaway MongoDB started in the Test stage
        MONGO_URI      = 'mongodb://localhost:27017/test_student_db'
        SECRET_KEY     = 'test-only'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.VERSION = sh(script: 'git rev-parse --short=8 HEAD', returnStdout: true).trim()
                }
                echo "Commit ${env.VERSION} on ${env.GIT_BRANCH}"
            }
        }

        stage('Build') {
            steps {
                sh '''
                  python3 -m venv .venv
                  . .venv/bin/activate
                  pip install --upgrade pip
                  pip install -r requirements.txt
                  python -m py_compile app.py
                '''
            }
        }

        stage('Test') {
            steps {
                // MongoDB shares the network of the Jenkins container, so it is on localhost:27017
                sh '''
                  docker rm -f mongo-test >/dev/null 2>&1 || true
                  docker run -d --rm --name mongo-test --network container:jenkins mongo:7.0
                  . .venv/bin/activate
                  for i in $(seq 1 30); do
                    python -c "import socket; socket.create_connection(('localhost', 27017), 1)" && break
                    sleep 2
                  done
                  mkdir -p reports
                  pytest -v --junitxml=reports/junit.xml
                '''
            }
            post {
                always {
                    junit 'reports/junit.xml'
                    sh 'docker rm -f mongo-test >/dev/null 2>&1 || true'
                }
            }
        }

        stage('Deploy to staging') {
            when {
                expression { env.GIT_BRANCH == 'origin/main' || env.GIT_BRANCH == 'main' }
            }
            steps {
                sh '''
                  test "$(aws sts get-caller-identity --query Account --output text)" = "$AWS_ACCOUNT_ID"

                  # 1. package the commit and upload it
                  git archive --format=tar.gz -o release.tar.gz HEAD
                  aws s3 cp release.tar.gz "s3://$DEPLOY_BUCKET/releases/jenkins-$VERSION.tar.gz" --region $AWS_REGION

                  # 2. find the staging server
                  INSTANCE_ID=$(aws ec2 describe-instances --region $AWS_REGION \
                    --filters "Name=tag:Name,Values=$STAGING_NAME" "Name=instance-state-name,Values=running" \
                    --query "Reservations[0].Instances[0].InstanceId" --output text)
                  STAGING_IP=$(aws ec2 describe-instances --region $AWS_REGION --instance-ids $INSTANCE_ID \
                    --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

                  # 3. run the deploy on the server through SSM (no SSH)
                  CMD_ID=$(aws ssm send-command --region $AWS_REGION --instance-ids $INSTANCE_ID \
                    --document-name AWS-RunShellScript --comment "jenkins build $BUILD_NUMBER" \
                    --parameters commands="aws s3 cp s3://$DEPLOY_BUCKET/releases/jenkins-$VERSION.tar.gz /tmp/release.tar.gz,mkdir -p /tmp/rel-$VERSION,tar -xzf /tmp/release.tar.gz -C /tmp/rel-$VERSION,bash /tmp/rel-$VERSION/deploy/remote-deploy.sh /tmp/release.tar.gz $VERSION staging" \
                    --query Command.CommandId --output text)
                  aws ssm wait command-executed --region $AWS_REGION --command-id $CMD_ID --instance-id $INSTANCE_ID || true
                  aws ssm get-command-invocation --region $AWS_REGION --command-id $CMD_ID --instance-id $INSTANCE_ID \
                    --query StandardOutputContent --output text
                  STATUS=$(aws ssm get-command-invocation --region $AWS_REGION --command-id $CMD_ID --instance-id $INSTANCE_ID --query Status --output text)
                  test "$STATUS" = "Success"

                  # 4. check it from outside
                  curl -fs "http://$STAGING_IP/health"
                  echo
                  echo "Staging URL: http://$STAGING_IP"
                '''
            }
        }
    }

    post {
        success {
            sh 'aws sns publish --region $AWS_REGION --topic-arn $SNS_TOPIC_ARN --subject "flask_Practice build #$BUILD_NUMBER SUCCESS" --message "Build #$BUILD_NUMBER of commit $VERSION passed Build, Test and Deploy to staging. $BUILD_URL" || true'
        }
        failure {
            sh 'aws sns publish --region $AWS_REGION --topic-arn $SNS_TOPIC_ARN --subject "flask_Practice build #$BUILD_NUMBER FAILED" --message "Build #$BUILD_NUMBER of commit $VERSION failed. Console: ${BUILD_URL}console" || true'
        }
        always {
            sh 'rm -f release.tar.gz'
        }
    }
}
