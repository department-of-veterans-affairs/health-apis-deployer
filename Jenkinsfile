
def saunter(scriptName) {
  withCredentials([
    usernameColonPassword(
      credentialsId: 'GITHUB_USERNAME_PASSWORD',
      variable: 'GITHUB_USERNAME_PASSWORD'),
    usernamePassword(
      credentialsId: 'HEALTH_APIS_RELEASES_NEXUS_USERNAME_PASSWORD',
      usernameVariable: 'NEXUS_USERNAME',
      passwordVariable: 'NEXUS_PASSWORD'),
    usernamePassword(
      credentialsId: 'DOCKER_USERNAME_PASSWORD',
      usernameVariable: 'DOCKER_USERNAME',
      passwordVariable: 'DOCKER_PASSWORD'),
    string(
      credentialsId: 'DOCKER_SOURCE_REGISTRY',
      variable: 'DOCKER_SOURCE_REGISTRY'),
    string(
      credentialsId: 'APP_CONFIG_AWS_ACCESS_KEY_ID',
      variable: 'AWS_ACCESS_KEY_ID'),
    string(
      credentialsId: 'APP_CONFIG_AWS_SECRET_ACCESS_KEY',
      variable: 'AWS_SECRET_ACCESS_KEY'),
    string(
      credentialsId: 'CRYPTO_KEY',
      variable: 'CRYPTO_KEY'),
    string(
      credentialsId: 'UC_CRYPTO_KEY',
      variable: 'UC_CRYPTO_KEY'),
    file(
      credentialsId: 'KUBERNETES_QA_SSH_KEY',
      variable: 'KUBERNETES_QA_SSH_KEY'),
    file(
      credentialsId: 'KUBERNETES_STAGING_LAB_SSH_KEY',
      variable: 'KUBERNETES_STAGING_LAB_SSH_KEY'),
    file(
      credentialsId: 'KUBERNETES_LAB_SSH_KEY',
      variable: 'KUBERNETES_LAB_SSH_KEY')
  ]) {
    sh script: scriptName
  }
}

def sendDeployMessage(channelName) {
  slackSend(
    channel: channelName,
    color: '#4682B4',
    message: "DEPLOYING - ${env.JOB_NAME} ${env.BUILD_NUMBER} (<${env.BUILD_URL}|Open>)\n${env.PRODUCT} is being deployed to ${env.ENVIRONMENT}"
  )
}

def notifySlackOfDeployment() {
  if (env.PRODUCT != "none" && env.PRODUCT != null) {
    if(["lab", "production"].contains(env.ENVIRONMENT)) {
      sendDeployMessage('api_operations')
    }
    sendDeployMessage('health_apis_jenkins')
  }
}

/*
 * We'll use the host user db so that any files written from the docker container look
 * like they were written by real host users.
 *
 * We also want to share the Maven repostory and SSH configuration, and finally we'll
 * need to be able to access docker. For that, we'll need to add the docker group, which
 * is currently 475, we'll need to mount the sock and need access to the rest of docker
 * lib for containers.
 */
final DOCKER_ARGS = "--privileged --group-add 497 -v /etc/passwd:/etc/passwd:ro -v /etc/group:/etc/group:ro -v /data/jenkins/.m2/repository:/root/.m2/repository -v /var/lib/jenkins/.ssh:/root/.ssh -v /var/run/docker.sock:/var/saunter/docker.sock -v /var/lib/docker:/var/lib/docker -v /etc/docker/daemon.json:/etc/docker/daemon.json"

pipeline {
  options {
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '99', artifactNumToKeepStr: '99'))
    retry(0)
    timeout(time: 1440, unit: 'MINUTES')
    timestamps()
  }
  parameters {
    booleanParam(name: 'DEBUG', defaultValue: false, description: "Enable debugging output")
    choice(name: 'PRODUCT', choices: ['none','data-query','exemplar','gal','squares','hotline','urgent-care','mock-ee'], description: "Install this product")
    choice(name: 'AVAILABILITY_ZONES', choices: ['all','us-gov-west-1a','us-gov-west-1b','us-gov-west-1c'], description: "Install into this availability zone")
    booleanParam(name: 'LEAVE_GREEN_ROUTES', defaultValue: false, description: "Leave the green load balancer attached to the last availability zone modified")
    booleanParam(name: 'SIMULATE_REGRESSION_TEST_FAILURE', defaultValue: false, description: "Force rollback logic by simulating a test failure.")
    booleanParam(name: 'FAST_AND_DANGEROUS_BUILD', defaultValue: false, description: "Perform a build to deploy a DU_VERSION with minimal steps. No testing, or validations.")
    string(name: 'FAST_AND_DANGEROUS_DU_VERSION', defaultValue: 'none', description: "Manual override of DU_VERSION for FAST_AND_DANGEROUS_BUILD." )
  }
  agent none
  triggers {
    upstream(upstreamProjects: 'department-of-veterans-affairs/health-apis/master', threshold: hudson.model.Result.SUCCESS)
  }
  environment {
    ENVIRONMENT = "${["qa", "lab", "staging-lab"].contains(env.BRANCH_NAME) ? env.BRANCH_NAME : "qa"}"
  }
  stages {
    /*
    * Make sure we're getting into an infinite loop of build, commit, build because we committed.
    */
    stage('C-C-C-Combo Breaker!') {
      agent {
        dockerfile {
           registryUrl 'https://index.docker.io/v1/'
           registryCredentialsId 'DOCKER_USERNAME_PASSWORD'
           args DOCKER_ARGS
        }
      }
      steps {
        script {
          /*
           * If you need the explanation for this, check out the function. Hard enough to explain once.
           * tl;dr Github web hooks could cause go in an infinite loop.
           */
           env.BUILD_MODE = 'build'
           if (checkBigBen()) {
             env.BUILD_MODE = 'ignore'
             /*
             * OK, this is a janky hack! We don't want this job. We didn't want
             * it to even start building, so we'll make it commit suicide! Build
             * numbers will skip, but whatever, that's better than every other
             * build being cruft.
             */
             currentBuild.result = 'NOT_BUILT'
             currentBuild.rawBuild.delete()
          }
        }
      }
    }
    stage('Set-up') {
      when { expression { return env.BUILD_MODE != 'ignore' } }
      steps {
        script {
          for(cause in currentBuild.rawBuild.getCauses()) {
            env['BUILD_'+cause.class.getSimpleName().replaceAll('(.+?)([A-Z])','$1_$2').toUpperCase()]=cause.getShortDescription()
          }
        }
      }
    }
    stage('Deploy') {
      when {
        allOf {
          expression { return env.BUILD_MODE != 'ignore' }
          expression { env.FAST_AND_DANGEROUS_BUILD == false }
          expression { env.FAST_AND_DANGEROUS_DU_VERSION == 'none' }
        }
      }
      agent {
        dockerfile {
            registryUrl 'https://index.docker.io/v1/'
            registryCredentialsId 'DOCKER_USERNAME_PASSWORD'
            args DOCKER_ARGS
           }
      }
      steps {
        notifySlackOfDeployment()
        saunter('./build.sh')
      }
    }
    stage('Danger Zone!') {
      when {
        beforeInput true
        allOf {
          expression { return env.BUILD_MODE != 'ignore' }
          expression { env.FAST_AND_DANGEROUS_BUILD != false }
          expression { env.FAST_AND_DANGEROUS_DU_VERSION != 'none' }
        }
      }
      input {
       message "I would like to enter the DANGER_ZONE..."
       ok "You may enter!"
       submitter "bryan.schofield,ian.laflamme"
      }
      agent {
        dockerfile {
            registryUrl 'https://index.docker.io/v1/'
            registryCredentialsId 'DOCKER_USERNAME_PASSWORD'
            args DOCKER_ARGS
           }
      }
      steps {
        echo "DANGER ZONE!"
      }
    }
  }
  post {
    always {
      node('master') {
        archiveArtifacts artifacts: '**/*-logs.zip', onlyIfSuccessful: false, allowEmptyArchive: true
        script {
          def buildName = sh returnStdout: true, script: '''[ -f .jenkins/build-name ] && cat .jenkins/build-name ; exit 0'''
          currentBuild.displayName = "#${currentBuild.number} - ${buildName}"
          def description = sh returnStdout: true, script: '''[ -f .jenkins/description ] && cat .jenkins/description ; exit 0'''
          currentBuild.description = "${description}"
          if (env.PRODUCT != "none") {
            sendNotifications()
          }
        }
      }
    }
  }
}
