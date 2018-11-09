pipeline {
  options {
    buildDiscarder(logRotator(numToKeepStr: '99', artifactNumToKeepStr: '99'))
    disableConcurrentBuilds()
    retry(0)
    timeout(time: 30, unit: 'MINUTES')
    timestamps()
  }
  agent {
    docker {
      registryUrl 'https://index.docker.io/v1/'
      registryCredentialsId 'DOCKER_USERNAME_PASSWORD'
      image 'vasdvp/health-apis-deployer:latest'
      args "-v /etc/passwd:/etc/passwd:ro -v /etc/group:/etc/group:ro --entrypoint=''"
    }
  }
  //triggers {
  //  upstream(upstreamProjects: 'lighthouse/beacon/develop', threshold: hudson.model.Result.SUCCESS)
  //}
  stages {
    stage('Deploy') {
      steps {
        withCredentials([
          usernamePassword(
            credentialsId: 'DOCKER_USERNAME_PASSWORD',
            usernameVariable: 'DOCKER_USERNAME',
            passwordVariable: 'DOCKER_PASSWORD')
        ]) {
          script {
            if (env.BRANCH_NAME == 'master') {
              sh script: './deployer.sh'
            }
          }
        }
      }
    }
  }
  post {
    always {
      archiveArtifacts artifacts: 'work/**', allowEmptyArchive: true
    }
    failure {
      script {
        if (env.BRANCH_NAME == 'master') {
          sendNotifications();
        }
      }
    }
    changed {
      script {
        if (env.BRANCH_NAME == 'master' && currentBuild.result != 'FAILURE') {
          sendNotifications();
        }
      }
    }
  }
}
