#!groovy​

// FULL_BUILD -> true/false build parameter to define if we need to run the entire stack for lab purpose only
// final FULL_BUILD = params.FULL_BUILD
// HOST_PROVISION -> server to run ansible based on provision/inventory.ini
final HOST_PROVISION = params.HOST_PROVISION

final GIT_URL = 'https://github.com/yashhere/jenkins-pipeline.git'

def tag
def app
def dockerfile
def anchorefile

pipeline {
 agent any

 // using the Timestamper plugin we can add timestamps to the console log
 options {
  timestamps()
 }

 environment {
  DOCKER_REPOSITORY = "yaagarwa/jenkins-pipeline"
  ANCHORE_ENGINE = "http://ip-172-31-24-101.ap-south-1.compute.internal:8228/v1"
 }

 stages {
  stage('Clone') {
   steps {
    checkout scm
    script {
     path = sh returnStdout: true, script: "pwd"
     path = path.trim()
     dockerfile = path + "/Dockerfile"
     anchorefile = path + "/anchore_images"
    }
   }
  }
  stage('Build') {
   steps {
    script {
     withEnv(["JAVA_HOME=${ tool 'jdk8' }", "PATH+MAVEN=${tool 'm3'}/bin"]) {
      def pom = readMavenPom file: 'pom.xml'
      sh "mvn -B versions:set -DnewVersion=${pom.version}-${BUILD_NUMBER}"
      sh "mvn -B -Dmaven.test.skip=true clean package"
      stash name: "artifact", includes: "target/vulnerablejavawebapp-*.jar"
     }
    }
   }
  }

  // stage('Unit Tests') {
  //  steps {
  //   script {
  //    withEnv(["JAVA_HOME=${ tool 'jdk8' }", "PATH+MAVEN=${tool 'm3'}/bin"]) {
  //     sh "mvn -B clean test"
  //     stash name: "unit_tests", includes: "target/surefire-reports/**"
  //    }
  //   }
  //  }
  // }

  // stage('Integration Tests') {
  //  steps {
  //   script {
  //    withEnv(["JAVA_HOME=${ tool 'jdk8' }", "PATH+MAVEN=${tool 'm3'}/bin"]) {
  //     sh "mvn -B clean verify -Dsurefire.skip=true"
  //     stash name: 'it_tests', includes: 'target/failsafe-reports/**'
  //    }
  //   }
  //  }
  // }

  stage('Static Analysis with SonarQube') {
   steps {
    script {
     withEnv(["JAVA_HOME=${ tool 'jdk8' }", "PATH+MAVEN=${tool 'm3'}/bin"]) {
      withSonarQubeEnv('SonarQube') {
       sh 'mvn sonar:sonar -DskipTests'
      }
     }
    }
   }
  }

  // stage('Analyze using Snyk') {
  //     steps {
  //         snykSecurity failOnIssues: false, snykInstallation: 'Snyk', snykTokenId: 'Snyk'
  //     }
  //     post {
  //         success {
  //             // we only worry about archiving the json file if the build steps are successful
  //             archiveArtifacts(artifacts: 'snyk*.json', allowEmptyArchive: true)
  //         }
  //     }
  // }

  stage('Building image') {
   steps {
    script {
     unstash 'artifact'
     tag = "${env.DOCKER_REPOSITORY}" + ":$BUILD_NUMBER"
     dockerImage = docker.build(tag)
    }
   }
  }

  stage('Analyze using Snyk') {
   steps {
    snykSecurity additionalArguments: "--docker" + " " + tag + " " + "--file" + "=" + dockerfile, failOnIssues: false, snykInstallation: 'Snyk', snykTokenId: 'Snyk'
   }
   post {
    success {
     // we only worry about archiving the json file if the build steps are successful
     archiveArtifacts(artifacts: 'snyk*.json', allowEmptyArchive: true)
    }
   }
  }

  stage('Upload Image') {
   steps {
    script {
     docker.withRegistry('', 'docker-credentials') {
      dockerImage.push()
     }
    }
   }
  }

  stage('Analyze using Anchore') {
   steps {
    writeFile file: anchorefile, text: "docker.io" + "/" + tag + " " + dockerfile
    anchore name: anchorefile,
     engineurl: "${ANCHORE_ENGINE}",
     engineCredentialsId: 'anchore-credentials',
     bailOnFail: false,
     annotations: [
      [key: 'added-by', value: 'jenkins']
     ]
   }
   post {
    success {
     // we only worry about archiving the json file if the build steps are successful
     archiveArtifacts(artifacts: 'anchore*.json', allowEmptyArchive: true)
    }
   }
  }

  stage('JAR Upload') {
   steps {
    script {
     unstash 'artifact'

     def pom = readMavenPom file: 'pom.xml'
     def file = "${pom.artifactId}-${pom.version}"
     def jar = "target/${file}.jar"

     sh "cp pom.xml ${file}.pom"

     nexusArtifactUploader artifacts: [
       [artifactId: "${pom.artifactId}", classifier: '', file: "target/${file}.jar", type: 'jar'],
       [artifactId: "${pom.artifactId}", classifier: '', file: "${file}.pom", type: 'pom']
      ],
      credentialsId: 'nexus',
      groupId: "${pom.groupId}",
      nexusUrl: NEXUS_URL,
      nexusVersion: 'nexus3',
      protocol: 'http',
      repository: 'ansible-vulnerable',
      version: "${pom.version}"
    }
   }
  }

  stage('Deploy') {
   steps {
    script {
      // install galaxy roles
      sh "ansible-galaxy install -vvv -r provision/requirements.yml -p provision/roles/"

      ansiblePlaybook colorized: true,
       credentialsId: 'ssh-jenkins',
       limit: "${HOST_PROVISION}",
       installation: 'ansible',
       inventory: 'provision/inventory.ini',
       playbook: 'provision/playbook.yml',
       become: true,
       becomeUser: 'jenkins',
       extraVars: [
        ansible_become_pass: [value: "${TARGET_SUDO_PASS}", hidden: true],
        container_name: "${tag}",
        container_image: "${tag}"
       ]
      disableHostKeyChecking: true
     }
    }
  }

  stage('Arachni') {
    steps {
      script {
        sh "mkdir -p $PWD/reports $PWD/arachni-artifacts"

        sh "docker run -v $PWD/reports:/arachni/reports ahannigan/docker-arachni bin/arachni --checks=*,-code_injection_php_input_wrapper,-ldap_injection,-no_sql*,-backup_files,-backup_directories,-captcha,-cvs_svn_users,-credit_card,-ssn,-localstart_asp,-webdav --plugin=autologin:url=https://${ARACHNI_TARGET_HOST}:${ARACHNI_TARGET_PORT}/login,parameters='login=user1@user1.com&password=abcd1234',check='Hi User 1|Logout' --scope-exclude-pattern='logout' --scope-exclude-pattern='resources' --session-check-pattern='Hi User 1' --session-check-url=https://${ARACHNI_TARGET_HOST}:${ARACHNI_TARGET_PORT} --http-user-agent='Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/51.0.2704.103 Safari/537.36' --report-save-path=reports/${pom.artifactId}.afr https://${ARACHNI_TARGET_HOST}:${ARACHNI_TARGET_PORT}"

        sh "docker run --name=arachni_report -v $PWD/reports:/arachni/reports ahannigan/docker-arachni bin/arachni_reporter reports/${pom.artifactId}.afr --reporter=json:outfile=reports/${pom.artifactId}-report.json;"

        sh "docker cp arachni_report:/arachni/reports/${pom.artifactId}-report.json $PWD/arachni-artifacts"

        sh "docker rm arachni_report"
      }
    }
    post {
    success {
     // we only worry about archiving the json file if the build steps are successful
     archiveArtifacts(artifacts: 'arachni-artifacts/**', fingerprint: true)
    }
   }
  }
 }
}
