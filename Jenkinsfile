
/*
 * We'll use the host user db so that any files written from the docker container look
 * like they were written by real host users.
 *
 * We also want to share the Maven repostory and SSH configuration, and finally we'll
 * need to be able to access docker. For that, we'll need to add the docker group, which
 * is currently 475, we'll need to mount the sock and need access to the rest of docker
 * lib for containers.
 */
final DOCKER_ARGS = """
  --privileged
  --group-add 497
  -v /etc/passwd:/etc/passwd:ro
  -v /etc/group:/etc/group:ro
  -v /data/jenkins/.m2/repository:/root/.m2/repository
  -v /var/lib/jenkins/.ssh:/root/.ssh \
  -v /var/run/docker.sock:/var/saunter/docker.sock
  -v /var/lib/docker:/var/lib/docker
  -v /etc/docker/daemon.json:/etc/docker/daemon.json
""".replaceAll( /\n\s*/, " " );


final CREDENTIALS = [
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
    credentialsId: 'SLACK_WEBHOOK',
    variable: 'SLACK_WEBHOOK' )
]


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
    string(name: 'DEPLOYER_VERSION', defaultValue: 'latest', description: 'Version of the deployment machinery')
    choice(name: 'VPC', choices: ["QA", "UAT", "Staging", "Production", "Staging-Lab", "Lab" ], description: "Environment to deploy into")
    string(name: 'ARTIFACT', defaultValue: 'NONE', description: "Maven coordinates to the Lamba to deploy")
  }
  agent none
  stages {
    stage('Set-up') {
      steps {
        script {
          for(cause in currentBuild.rawBuild.getCauses()) {
            env['BUILD_'+cause.class.getSimpleName().replaceAll('(.+?)([A-Z])','$1_$2').toUpperCase()]=cause.getShortDescription()
          }
        }
      }
    }
    stage('Deploy') {
      when { not { environment name: 'ARTIFACT', value: 'NONE' } }
      agent {
        docker {
          registryUrl 'https://index.docker.io/v1/'
          registryCredentialsId 'DOCKER_USERNAME_PASSWORD'
          image "vasdvp/health-apis-deploy-tools:${env.DEPLOYER_VERSION}"
          args DOCKER_ARGS
        }
      }
      steps {
        withCredentials( CREDENTIALS ) {
          sh script: './build.sh'
        }
      }
    }
  }
  post {
    always {
      node('master') {
        script {
          def buildName = sh returnStdout: true, script: '''[ -f .deployment/build-name ] && cat .deployment/build-name ; exit 0'''
          currentBuild.displayName = "#${currentBuild.number} - ${buildName}"
          def description = sh returnStdout: true, script: '''[ -f .deployment/description ] && cat .deployment/description ; exit 0'''
          currentBuild.description = "${description}"
          def unstableStatus = sh returnStatus: true, script: '''[ -f .deployment/unstable ] && exit 1 ; exit 0'''
          if (unstableStatus == 1 && currentBuild.result != 'FAILURE') {
            currentBuild.result = 'UNSTABLE';
          }
        }
        archiveArtifacts artifacts: '.deployment/artifacts/**', onlyIfSuccessful: false, allowEmptyArchive: true
        withCredentials( CREDENTIALS ) {
          script {
            if (env.ARTIFACT != 'NONEx') {
              sendNotifications( [ "shanktovoid@${SLACK_WEBHOOK}" ] )
            }
          }
        }
      }
    }
  }
}
