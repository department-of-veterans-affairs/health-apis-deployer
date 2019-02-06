pipeline {
  options {
    buildDiscarder(logRotator(numToKeepStr: '99', artifactNumToKeepStr: '99'))
    disableConcurrentBuilds()
    retry(0)
    timeout(time: 30, unit: 'MINUTES')
    timestamps()
  }
  parameters {
    booleanParam(name: 'AUTO_UPGRADE_HEALTH_APIS', defaultValue: false, description: 'Automatically upgrade to the latest version of Health API applications')
    booleanParam(name: 'TEST_FUNCTIONAL', defaultValue: true, description: 'Perform functional tests')
    booleanParam(name: 'TEST_CRAWL', defaultValue: true, description: 'Perform resource crawl')
    string(name: 'MR_URL', defaultValue: '', description: 'URL to Maintenance Request Pull Request for this change')
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
/*
    cron('00 22 * * 1-5')
*/
    upstream(upstreamProjects: 'department-of-veterans-affairs/health-apis/master', threshold: hudson.model.Result.SUCCESS)
  }
  stages {
    /*
     * Make sure we're getting into an infinite loop of build, commit, build because we committed.
     */
    stage('C-C-C-Combo Breaker!') {
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
      } // steps
    } // stage
    stage('Deploy') {
      when { expression { return env.BUILD_MODE != 'ignore' } }
      steps {
        withCredentials([
          usernameColonPassword(
            credentialsId: 'GITHUB_USERNAME_PASSWORD',
            variable: 'GITHUB_USERNAME_PASSWORD'),
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
          usernamePassword(
            credentialsId: 'QA_IDS_DB_USERNAME_PASSWORD',
            usernameVariable: 'QA_IDS_DB_USERNAME',
            passwordVariable: 'QA_IDS_DB_PASSWORD'),
          usernamePassword(
            credentialsId: 'PROD_IDS_DB_USERNAME_PASSWORD',
            usernameVariable: 'PROD_IDS_DB_USERNAME',
            passwordVariable: 'PROD_IDS_DB_PASSWORD'),
          usernamePassword(
            credentialsId: 'LAB_IDS_DB_USERNAME_PASSWORD',
            usernameVariable: 'LAB_IDS_DB_USERNAME',
            passwordVariable: 'LAB_IDS_DB_PASSWORD'),
          usernamePassword(
            credentialsId: 'QA_CDW_USERNAME_PASSWORD',
            usernameVariable: 'QA_CDW_USERNAME',
            passwordVariable: 'QA_CDW_PASSWORD'),
          usernamePassword(
            credentialsId: 'PROD_CDW_USERNAME_PASSWORD',
            usernameVariable: 'PROD_CDW_USERNAME',
            passwordVariable: 'PROD_CDW_PASSWORD'),
          usernamePassword(
            credentialsId: 'LAB_CDW_USERNAME_PASSWORD',
            usernameVariable: 'LAB_CDW_USERNAME',
            passwordVariable: 'LAB_CDW_PASSWORD'),
          string(
            credentialsId: 'PROD_HEALTH_API_CERTIFICATE_PASSWORD',
            variable: 'PROD_HEALTH_API_CERTIFICATE_PASSWORD'),
          string(
            credentialsId: 'HEALTH_API_CERTIFICATE_PASSWORD',
            variable: 'HEALTH_API_CERTIFICATE_PASSWORD'),
          string(
            credentialsId: 'OPENSHIFT_API_TOKEN',
            variable: 'OPENSHIFT_API_TOKEN'),
          string(
            credentialsId: 'APP_CONFIG_AWS_ACCESS_KEY_ID',
            variable: 'AWS_ACCESS_KEY_ID'),
          string(
            credentialsId: 'APP_CONFIG_AWS_SECRET_ACCESS_KEY',
            variable: 'AWS_SECRET_ACCESS_KEY'),
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
            variable: 'ARGONAUT_CLIENT_SECRET'),
          string(
            credentialsId: 'LAB_CLIENT_ID',
            variable: 'LAB_CLIENT_ID'),
          string(
            credentialsId: 'LAB_CLIENT_SECRET',
            variable: 'LAB_CLIENT_SECRET'),
          string(
            credentialsId: 'LAB_USER_PASSWORD',
            variable: 'LAB_USER_PASSWORD')
        ]) {
          script {
            for(cause in currentBuild.rawBuild.getCauses()) {
              env['BUILD_'+cause.class.getSimpleName().replaceAll('(.+?)([A-Z])','$1_$2').toUpperCase()]=cause.getShortDescription()
            }
            if (env.BRANCH_NAME == 'master' || env.BRANCH_NAME == 'x/upgraderator') {
              sh script: './build.sh'
            }
          }
        }
      }
    }
  }
  post {
    always {
//      archiveArtifacts artifacts: '**/*', onlyIfSuccessful: false, allowEmptyArchive: true

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
