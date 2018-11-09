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
       /*
        * We'll use the host user db so that any files written from the docker container look
        * like they were written by real host users.
        *
        * We also want to share the Maven repostory and SSH configuration, and finally we'll
        * need to be able to access docker. For that, we'll need to add the docker group, which
        * is currently 475, we'll need to mount the sock and need access to the rest of docker
        * lib for containers.
        */
       registryUrl 'https://index.docker.io/v1/'
      registryCredentialsId 'DOCKER_USERNAME_PASSWORD'
      image 'vasdvp/health-apis-deployer:latest'
      args "--privileged --group-add 497 -v /etc/passwd:/etc/passwd:ro -v /etc/group:/etc/group:ro -v /data/jenkins/.m2/repository:/root/.m2/repository -v /var/lib/jenkins/.ssh:/root/.ssh -v /var/run/docker.sock:/var/run/docker.sock -v /var/lib/docker:/var/lib/docker"
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
            passwordVariable: 'DOCKER_PASSWORD'),
        string(
            credentialsId: 'DOCKER_SOURCE_REGISTRY',
            variable: 'DOCKER_SOURCE_REGISTRY')
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
