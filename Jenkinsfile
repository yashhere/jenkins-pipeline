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

  // Keep only the last 10 build to preserve space
  buildDiscarder(logRotator(numToKeepStr: '10', artifactNumToKeepStr: '30'))

  // Don't run concurrent builds for a branch, because they use the same workspace directory
  disableConcurrentBuilds()
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

  stage('Artifactory configuration') {
   steps {
    rtMavenDeployer(
     id: "MAVEN_DEPLOYER",
     serverId: ARTIFACTORY_SERVER_ID,
     releaseRepo: "vulnerableapp-integration",
     snapshotRepo: "vulnerableapp-snapshot"
    )

    rtMavenResolver(
     id: "MAVEN_RESOLVER",
     serverId: ARTIFACTORY_SERVER_ID,
     releaseRepo: "vulnerableapp-integration",
     snapshotRepo: "vulnerableapp-snapshot"
    )
   }
  }


    stage('Building image') {
     steps {
      script {
       tag = "${env.DOCKER_REPOSITORY}" + ":$BUILD_NUMBER"
       dockerImage = docker.build(tag)
      }
     }
    }
    
    stage('Build JAR') {
     steps {
      script {
       withEnv(["JAVA_HOME=${ tool 'jdk8' }", "PATH+MAVEN=${tool 'm3'}/bin"]) {
        def pom = readMavenPom file: 'pom.xml'
        rtMavenRun(
         pom: 'pom.xml',
         goals: '-B -Dmaven.test.skip=true clean package -Dartifactory.publish.buildInfo=true',
         deployerId: "MAVEN_DEPLOYER"
        )
       }
      }
     }
     post {
      success {
       // we only worry about archiving the json file if the build steps are successful
       archiveArtifacts(artifacts: 'target/*.json', allowEmptyArchive: true)
       archiveArtifacts(artifacts: 'target/*.jar', allowEmptyArchive: true)
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

  stage('Upload Image') {
   steps {
    script {
     docker.withRegistry('', 'docker-credentials') {
      dockerImage.push()
     }
    }
   }
  }


  stage('Run Analysis') {
   parallel {
    stage('Static Analysis with SonarQube') {
     steps {
      analyzeWithSonarQubeAndWaitForQualityGoal()
      // script {
      //  withEnv(["JAVA_HOME=${ tool 'jdk8' }", "PATH+MAVEN=${tool 'm3'}/bin"]) {
      //   withSonarQubeEnv('SonarQube') {
      //    sh 'mvn sonar:sonar -DskipTests'
      //   }
      //  }
      // }
     }
    }

    stage('Analyse using Snyk') {
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

    stage('Analyse using Anchore') {
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
   }
  }



  stage('Deploy') {
   when {
    expression {
     return currentBuild.currentResult == 'SUCCESS'
    }
   }
   steps {
    script {
     def pom = readMavenPom file: 'pom.xml'

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
      extras: '--force',
      extraVars: [
       ansible_become_pass: [value: "${TARGET_SUDO_PASS}", hidden: true],
       container_name: "${pom.artifactId}",
       container_image: "${tag}"
      ]
     disableHostKeyChecking: true
    }
   }
  }

  stage('Scan with Arachni') {
   steps {
    sleep time: 2, unit: 'MINUTES'

    script {
     def pom = readMavenPom file: 'pom.xml'
     def workspace = pwd()

     sh "docker run -v ${workspace}:/arachni/reports ahannigan/docker-arachni bin/arachni --checks=*,-code_injection_php_input_wrapper,-ldap_injection,-no_sql*,-backup_files,-backup_directories,-captcha,-cvs_svn_users,-credit_card,-ssn,-localstart_asp,-webdav --plugin=autologin:url=https://${ARACHNI_TARGET_HOST}:${ARACHNI_TARGET_PORT}/login,parameters='login=user1@user1.com&password=abcd1234',check='Hi User 1|Logout' --scope-exclude-pattern='logout' --scope-exclude-pattern='resources' --session-check-pattern='Hi User 1' --session-check-url=https://${ARACHNI_TARGET_HOST}:${ARACHNI_TARGET_PORT} --http-user-agent='Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/51.0.2704.103 Safari/537.36' --report-save-path=reports/${pom.artifactId}-arachni-scan-report.afr https://${ARACHNI_TARGET_HOST}:${ARACHNI_TARGET_PORT}"

     sh "docker run --name=arachni_report -v ${workspace}:/arachni/reports ahannigan/docker-arachni bin/arachni_reporter reports/${pom.artifactId}-arachni-scan-report.afr --reporter=json:outfile=reports/${pom.artifactId}-arachni-scan-report.json;"

     sh "docker rm arachni_report"
    }
   }
   post {
    success {
     // we only worry about archiving the json file if the build steps are successful
     archiveArtifacts(artifacts: '*arachni-scan-report.json')
    }
   }
  }
 }
 
 post {
        always {
            script {
                echo "${env.JENKINS_HOME}"
                echo "${env.WORKSPACE}"
                directory = "${env.JENKINS_HOME}" + "/jobs/" + "${JOB_NAME}" + "/builds/" + "${BUILD_NUMBER}" + "/archive/"
                dir(directory) {
                    findFiles(glob: '**/*.json')
                    sh "ls -la"
                }
                withAWS(region: 'ap-south-1', credentials: 'aws-s3') {
                    identity = awsIdentity(); //Log AWS credentials
                    // Upload files from working directory 'dist' in your project workspace
                    s3Upload(bucket: "grafeas", path: "anchore/" + "${JOB_NAME}" + "-" + "${BUILD_NUMBER}", includePathPattern: 'AnchoreReport*/anchore*.json', workingDir: directory);

                    s3Upload(bucket: "grafeas", path: "snyk/" + "${JOB_NAME}" + "-" + "${BUILD_NUMBER}", includePathPattern: 'snyk*.json', workingDir: directory);
                    s3Upload(bucket: "grafeas", path: "arachni/" + "${JOB_NAME}" + "-" + "${BUILD_NUMBER}", includePathPattern: '*arachni*.json', workingDir: directory);
                }
            }
        }
    }
}

void analyzeWithSonarQubeAndWaitForQualityGoal() {
 withEnv(["JAVA_HOME=${ tool 'jdk8' }", "PATH+MAVEN=${tool 'm3'}/bin"]) {
  withSonarQubeEnv('SonarQube') {
   sh 'mvn sonar:sonar -DskipTests'
  }
  // timeout(time: 2, unit: 'MINUTES') { // Normally, this takes only some ms. sonarcloud.io might take minutes, though :-(
  //  def qg = waitForQualityGate()
  //  if (qg.status != 'OK') {
  //   echo "Pipeline unstable due to quality gate failure: ${qg.status}"
  //   currentBuild.result = 'UNSTABLE'
  //  }
  // }
 }
}
