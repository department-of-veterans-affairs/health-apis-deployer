pipeline {
  options {
    buildDiscarder(logRotator(numToKeepStr: '99', artifactNumToKeepStr: '99'))
    disableConcurrentBuilds()
    retry(0)
    timeout(time: 30, unit: 'MINUTES')
    timestamps()
  }
  agent {
    dockerfile {
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
      args "--privileged --group-add 497 -v /etc/passwd:/etc/passwd:ro -v /etc/group:/etc/group:ro -v /data/jenkins/.m2/repository:/root/.m2/repository -v /var/lib/jenkins/.ssh:/root/.ssh -v /var/run/docker.sock:/var/run/docker.sock -v /var/lib/docker:/var/lib/docker -v /etc/docker/daemon.json:/etc/docker/daemon.json"
     }
  }
  triggers {
    upstream(upstreamProjects: 'department-of-veterans-affairs/health-apis/master', threshold: hudson.model.Result.SUCCESS)
  }
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
            variable: 'DOCKER_SOURCE_REGISTRY'),
          usernamePassword(
            credentialsId: 'OPENSHIFT_USERNAME_PASSWORD',
            usernameVariable: 'OPENSHIFT_USERNAME',
            passwordVariable: 'OPENSHIFT_PASSWORD'),
          string(
            credentialsId: 'OPENSHIFT_API_TOKEN',
            variable: 'OPENSHIFT_API_TOKEN'),
          string(
            credentialsId: 'ARGONAUT_TOKEN',
            variable: 'ARGONAUT_TOKEN'),
          string(
            credentialsId: 'ARGONAUT_REFRESH_TOKEN',
            variable: 'ARGONAUT_REFRESH_TOKEN'),
          string(
            credentialsId: 'ARGONAUT_CLIENT_ID',
            variable: 'ARGONAUT_CLIENT_ID'),
          string(
            credentialsId: 'ARGONAUT_CLIENT_SECRET',
            variable: 'ARGONAUT_CLIENT_SECRET')
        ]) {
          script {
            if (env.BRANCH_NAME == 'master' || env.BRANCH_NAME == 'lab') {
              sh script: './deployer.sh'
            }
          }
        }
      }
    }
  }
  post {
    always {
      archiveArtifacts artifacts: '**/*', onlyIfSuccessful: false, allowEmptyArchive: true
      script {
        def buildName = sh returnStdout: true, script: '''[ -f .jenkins/build-name ] && cat .jenkins/build-name ; exit 0'''
        currentBuild.displayName = "#${currentBuild.number} - ${buildName}"
        def description = sh returnStdout: true, script: '''[ -f .jenkins/description ] && cat .jenkins/description ; exit 0'''
        currentBuild.description = "${description}"
      }
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
