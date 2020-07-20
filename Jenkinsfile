
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

def contentOf(file) {
  if (fileExists(file)) {
    return readFile(file).trim()
  }
  return ''
}

pipeline {
  agent none
  options {
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '99', artifactNumToKeepStr: '99'))
    retry(0)
    timeout(time: 1440, unit: 'MINUTES')
    timestamps()
  }
  parameters {
    booleanParam(name: 'DEBUG', defaultValue: false, description: "Enable debugging output")
    string(name: 'DEPLOYER_VERSION', defaultValue: '14-NR-1.0.47-SNAPSHOT', description: 'Version of the deployment machinery')
    choice(name: 'VPC', choices: ["QA", "UAT", "Staging", "Production", "Staging-Lab", "Lab" ],
      description: "Environment to deploy into")
    string(name: 'PRODUCT', defaultValue: 'exemplar', description: "The product to deploy.")
  }
  stages {
    stage('Run') {
      agent {
        docker {
          registryUrl 'https://index.docker.io/v1/'
          registryCredentialsId 'DOCKER_USERNAME_PASSWORD'
          image "vasdvp/health-apis-deploy-tools:${env.DEPLOYER_VERSION}"
          args DOCKER_ARGS
        }
      }
      steps {
        script {
          if ( env.VPC == null ) { env.VPC = "QA" }
          currentBuild.displayName = "#${currentBuild.number} - ${env.VPC} - in progress"
          for(cause in currentBuild.rawBuild.getCauses()) {
            def name='BUILD_'+cause.class.getSimpleName().replaceAll('(.+?)([A-Z])','$1_$2').toUpperCase()
            env[name]=cause.getShortDescription()
          }
        }
        lock("deploy-${env.VPC}") {
          withCredentials( CREDENTIALS ) {
            sh script: './build.sh'
          }
        }
      }
    }
  }
  post {
    always {
      node('master') {
        script {
          currentBuild.displayName = "#${currentBuild.number} - " + contentOf('.deployment/build-name')
          currentBuild.description = contentOf('.deployment/description')
          def unstable = contentOf('.deployment/unstable')
          if (unstable != '' && currentBuild.result != 'FAILURE') {
            currentBuild.result = 'UNSTABLE';
            currentBuild.description += "Unstable because: " + unstable
          }
        }
        archiveArtifacts artifacts: '.deployment/artifacts/**', onlyIfSuccessful: false, allowEmptyArchive: true
        withCredentials( CREDENTIALS ) {
          script {
            sendNotifications( [ "shanktovoid@${SLACK_WEBHOOK}" ] )
          }
        }
      }
    }
  }
}
