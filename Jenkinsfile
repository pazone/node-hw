#!/usr/bin/env groovy
@Library('apm@current') _

pipeline {
  agent { label 'linux && immutable' }
  environment {
    REPO = 'node-hw'
    BASE_DIR = "src/github.com/pazone/${env.REPO}"
    PIPELINE_LOG_LEVEL='INFO'
    JOB_GCS_BUCKET = credentials('gcs-bucket')
    GITHUB_CHECK_ITS_NAME = 'Integration Tests'
    ITS_PIPELINE = 'apm-integration-tests-selector-mbp/main'
    OPBEANS_REPO = 'opbeans-node'
    GITHUB_CHECK = 'true'
    // todo: change
    RELEASE_URL_MESSAGE = "(<https://github.com/pazone/${env.REPO}/releases/tag/${env.TAG_NAME}|${env.TAG_NAME}>)"
    // todo: change
    SLACK_CHANNEL = '#apm-agent-node'
    // todo: change
    NOTIFY_TO = 'pavel.zorin@elastic.co'
    TOTP_SECRET = 'totp/code/npmjs-elasticmachine'
  }
  options {
    timeout(time: 3, unit: 'HOURS')
    buildDiscarder(logRotator(numToKeepStr: '20', artifactNumToKeepStr: '20', daysToKeepStr: '30'))
    timestamps()
    ansiColor('xterm')
    disableResume()
    durabilityHint('PERFORMANCE_OPTIMIZED')
    rateLimitBuilds(throttle: [count: 60, durationName: 'hour', userBoost: true])
    quietPeriod(10)
  }
  triggers {
    issueCommentTrigger("(${obltGitHubComments()}|^run (module|benchmark) tests.*)")
  }
  parameters {
    booleanParam(name: 'Run_As_Main_Branch', defaultValue: false, description: 'Allow to run any steps on a PR, some steps normally only run on main branch.')
    booleanParam(name: 'bench_ci', defaultValue: true, description: 'Enable benchmarks.')
    booleanParam(name: 'tav_ci', defaultValue: true, description: 'Enable TAV tests.')
    booleanParam(name: 'tests_ci', defaultValue: true, description: 'Enable tests.')
    booleanParam(name: 'test_edge_ci', defaultValue: true, description: 'Enable tests for edge versions of nodejs.')
  }
  stages {
    /**
    Checkout the code and stash it, to use it on other stages.
    */
    stage('Checkout') {
      options { skipDefaultCheckout() }
      steps {
        pipelineManager([ cancelPreviousRunningBuilds: [ when: 'PR' ] ])
        deleteDir()
        gitCheckout(basedir: "${BASE_DIR}", githubNotifyFirstTimeContributor: true,
                    shallow: false, reference: "/var/lib/jenkins/.git-references/${REPO}.git")
        stash allowEmpty: true, name: 'source', useDefaultExcludes: false, excludes: '.git'
        script {
          dir("${BASE_DIR}"){
            def regexps =[
              "^lib/instrumentation/modules/",
              "^test/instrumentation/modules/"
            ]
            env.TAV_UPDATED = isGitRegionMatch(patterns: regexps)

            // Skip all the stages except docs for PR's with asciidoc or md changes only
            env.ONLY_DOCS = isGitRegionMatch(patterns: [ '.*\\.(asciidoc|md)' ], shouldMatchAll: true)
          }
        }
      }
    }
    /**
      Run tests.
    */
    stage('Test') {
      options { skipDefaultCheckout() }
      environment {
        HOME = "${env.WORKSPACE}"
      }
      when {
        beforeAgent true
        allOf {
          not { tag pattern: 'v\\d+\\.\\d+\\.\\d+', comparator: 'REGEXP' }
          expression { return env.ONLY_DOCS == "false" }
          expression { return params.tests_ci }
          // todo: remove
          expression { return false }
        }
      }
      steps {
        withGithubNotify(context: 'Test', tab: 'tests') {
          deleteDir()
          unstash 'source'
          dir("${BASE_DIR}"){
            script {
              def node = readYaml(file: '.ci/.jenkins_nodejs.yml')
              def parallelTasks = [:]
              node['NODEJS_VERSION'].each{ version ->
                parallelTasks["Node.js-${version}"] = generateStep(version: version)
                parallelTasks["Node.js-${version}-async-hooks-false"] = generateStep(version: version, disableAsyncHooks: true)
                // TODO: to be enabled if required.
                // parallelTasks["Windows-Node.js-${version}"] = generateStepForWindows(version: version)
              }

              // Only 14 for the time being
              parallelTasks["Windows-Node.js-14"] = generateStepForWindows(version: '14')

              // Linting in parallel with the test stage
              parallelTasks['linting'] = linting()

              parallel(parallelTasks)
            }
          }
        }
      }
    }
    /**
      Run TAV tests.
    */
    stage('TAV Test') {
      options { skipDefaultCheckout() }
      environment {
        HOME = "${env.WORKSPACE}"
      }
      when {
        beforeAgent true
        allOf {
          not { tag pattern: 'v\\d+\\.\\d+\\.\\d+', comparator: 'REGEXP' }
          anyOf {
            expression { return params.Run_As_Main_Branch }
            triggeredBy 'TimerTrigger'
            changeRequest()
            expression { return env.TAV_UPDATED != "false" }
          }
          expression { return params.tav_ci }
          expression { return env.ONLY_DOCS == "false" }
          // todo: change
          expression { return false }
        }
      }
      steps {
        deleteDir()
        unstash 'source'
        dir("${BASE_DIR}"){
          script {
            def tavContext = getSmartTAVContext()
            withGithubNotify(context: tavContext.ghContextName, description: tavContext.ghDescription, tab: 'tests') {
              def parallelTasks = [:]
              tavContext.node['NODEJS_VERSION'].each{ version ->
                tavContext.tav['TAV'].each{ tav_item ->
                  parallelTasks["Node.js-${version}-${tav_item}"] = generateStep(version: version, tav: tav_item)
                }
              }
              parallel(parallelTasks)
            }
          }
        }
      }
    }

    /**
      The "Edge Test" is a run of the agent test suite with pre-release builds
      of node.js, if available and useful. "Pre-release" builds are release
      candidate (RC) and "nightly" node.js builds.
    */
    stage('Edge Test') {
      options { skipDefaultCheckout() }
      environment {
        HOME = "${env.WORKSPACE}"
      }
      when {
        beforeAgent true
        allOf {
          not { tag pattern: 'v\\d+\\.\\d+\\.\\d+', comparator: 'REGEXP' }
          anyOf {
            expression { return params.Run_As_Main_Branch }
            triggeredBy 'TimerTrigger'
          }
          expression { return params.test_edge_ci }
          expression { return env.ONLY_DOCS == "false" }
          // todo: change
          expression {return false }
        }
      }
      parallel {
        stage('Nightly Test') {
          agent { label 'linux && immutable' }
          steps {
            withGithubNotify(context: 'Nightly Test', tab: 'tests') {
              deleteDir()
              unstash 'source'
              dir("${BASE_DIR}"){
                script {
                  def node = readYaml(file: '.ci/.jenkins_nightly_nodejs.yml')
                  def parallelTasks = [:]
                  node['NODEJS_VERSION'].each { version ->
                    parallelTasks["Node.js-${version}-nightly"] = generateStep(version: version, buildType: 'nightly')
                  }
                  parallel(parallelTasks)
                }
              }
            }
          }
        }
        stage('Nightly Test - No async hooks') {
          agent { label 'linux && immutable' }
          steps {
            withGithubNotify(context: 'Nightly No Async Hooks Test', tab: 'tests') {
              deleteDir()
              unstash 'source'
              dir("${BASE_DIR}"){
                script {
                  def node = readYaml(file: '.ci/.jenkins_nightly_nodejs.yml')
                  def parallelTasks = [:]
                  node['NODEJS_VERSION'].each { version ->
                    parallelTasks["Node.js-${version}-nightly-no-async-hooks"] = generateStep(version: version, buildType: 'nightly', disableAsyncHooks: true)
                  }
                  parallel(parallelTasks)
                }
              }
            }
          }
        }
        stage('RC Test') {
          agent { label 'linux && immutable' }
          steps {
            withGithubNotify(context: 'RC Test', tab: 'tests') {
              deleteDir()
              unstash 'source'
              dir("${BASE_DIR}"){
                script {
                  def node = readYaml(file: '.ci/.jenkins_rc_nodejs.yml')
                  def parallelTasks = [:]
                  node['NODEJS_VERSION'].each { version ->
                    parallelTasks["Node.js-${version}-rc"] = generateStep(version: version, buildType: 'rc')
                  }
                  parallel(parallelTasks)
                }
              }
            }
          }
        }
        stage('RC Test - No async hooks') {
          agent { label 'linux && immutable' }
          steps {
            withGithubNotify(context: 'RC No Async Hooks Test', tab: 'tests') {
              deleteDir()
              unstash 'source'
              dir("${BASE_DIR}"){
                script {
                  def node = readYaml(file: '.ci/.jenkins_rc_nodejs.yml')
                  def parallelTasks = [:]
                  node['NODEJS_VERSION'].each { version ->
                    parallelTasks["Node.js-${version}-rc-no-async-hooks"] = generateStep(version: version, buildType: 'rc', disableAsyncHooks: true)
                  }
                  parallel(parallelTasks)
                }
              }
            }
          }
        }
      }
    }
    stage('Integration Tests') {
      agent none
      when {
        beforeAgent true
        allOf {
          not { tag pattern: 'v\\d+\\.\\d+\\.\\d+', comparator: 'REGEXP' }
          expression { return env.ONLY_DOCS == "false" }
          anyOf {
            changeRequest()
            expression { return !params.Run_As_Main_Branch }
          }
          expression { return false }
        }
      }
      steps {
        build(job: env.ITS_PIPELINE, propagate: false, wait: false,
              parameters: [string(name: 'INTEGRATION_TEST', value: 'Node.js'),
                           string(name: 'BUILD_OPTS', value: "--nodejs-agent-package ${env.CHANGE_FORK?.trim() ?: 'elastic' }/${env.REPO}#${env.GIT_BASE_COMMIT} --opbeans-node-agent-branch ${env.GIT_BASE_COMMIT}"),
                           string(name: 'GITHUB_CHECK_NAME', value: env.GITHUB_CHECK_ITS_NAME),
                           string(name: 'GITHUB_CHECK_REPO', value: env.REPO),
                           string(name: 'GITHUB_CHECK_SHA1', value: env.GIT_BASE_COMMIT)])
        githubNotify(context: "${env.GITHUB_CHECK_ITS_NAME}", description: "${env.GITHUB_CHECK_ITS_NAME} ...", status: 'PENDING', targetUrl: "${env.JENKINS_URL}search/?q=${env.ITS_PIPELINE.replaceAll('/','+')}")
      }
    }
    stage('Release') {
      options { skipDefaultCheckout() }
      when {
        beforeAgent true
        tag pattern: 'v\\d+\\.\\d+\\.\\d+', comparator: 'REGEXP'
      }
      environment {
        SUFFIX_ARN_FILE = 'arn-file.md'
      }
      stages {
        stage('Opbeans') {
          environment {
            REPO_NAME = "${OPBEANS_REPO}"
          }
          when {
            // todo
            expression {return false }
          }
          steps {            
            deleteDir()
            dir("${OPBEANS_REPO}"){
              git(credentialsId: 'f6c7695a-671e-4f4f-a331-acdce44ff9ba',
                  url: "git@github.com:elastic/${OPBEANS_REPO}.git",
                  branch: 'main')
              // It's required to transform the tag value to the artifact version
              sh script: ".ci/bump-version.sh ${env.BRANCH_NAME.replaceAll('^v', '')}", label: 'Bump version'
              // The opbeans pipeline will trigger a release for the main branch
              gitPush()
              // The opbeans pipeline will trigger a release for the release tag
              gitCreateTag(tag: "${env.BRANCH_NAME}")
            }
          }
        }
        stage('Dist') {
          when {
            expression { return false }
          }
          steps {
            withGithubNotify(context: "Dist") {
              setEnvVar('ELASTIC_LAYER_NAME', "elastic-apm-node${getVersion()}")
              setEnvVar('RELEASE_NOTES_URL', getReleaseNotesUrl())
              deleteDir()
              unstash 'source'
              withNodeJSEnv(version: 'v14.17.5'){
                dir("${BASE_DIR}"){
                  cmd(label: 'make dist', script: 'make -C .ci dist')
                }
              }
            }
          }
        }
        stage('Publish to AWS') {
          when {
            expression { return false }
          }
          steps {
            withGithubNotify(context: "Publish") {
              withGoEnv(){
                withAWSEnv(secret: 'secret/observability-team/ci/service-account/apm-aws-lambda', forceInstallation: true, version: '2.4.10') {
                  dir("${BASE_DIR}"){
                    cmd(label: 'make publish-in-all-aws-regions', script: 'make -C .ci publish-in-all-aws-regions')
                    cmd(label: 'make create-arn-file', script: 'make -C .ci create-arn-file')
                  }
                }
              }
            }
          }
          post {
            always {
              archiveArtifacts(allowEmptyArchive: true, artifacts: "${BASE_DIR}/build/aws")
            }
          }
        }
        stage('Release Notes') {
          when {
            expression { return false }
          }
          steps {
            withGhEnv(forceInstallation: true, version: '2.4.0') {
              dir("${BASE_DIR}"){
                cmd(label: 'make release-notes', script: 'make -C .ci release-notes')
              }
            }
          }
        }
        stage('Publish to npm') {
          steps {
            deleteDir()
            unstash 'source'
            sh 'ls -lah'
            withTotpVault(secret: "${env.TOTP_SECRET}", code_var_name: 'TOTP_CODE') {              
              cmd(label: 'make npm-publish', script: 'make -C .ci npm-publish')
            }
          }
        }
      }
      post {
        success {
          whenTrue(isTag()) {
            // notifyStatus(slackStatus: 'good', subject: "[${env.REPO}] Release *${env.TAG_NAME}* published", body: "Build: (<${env.RUN_DISPLAY_URL}|here>)\nRelease URL: ${env.RELEASE_URL_MESSAGE}")
          }
        }
        failure {
          whenTrue(isTag()) {
            // notifyStatus(slackStatus: 'warning', subject: "[${env.REPO}] Release *${env.TAG_NAME}* could not be published.", body: "Build: (<${env.RUN_DISPLAY_URL}|here>)")
          }
        }
      }
    }
    /**
      Run the benchmarks and store the results on ES.
      The result JSON files are also archive into Jenkins.
    */
    stage('Benchmarks') {      
      agent { label 'metal' }
      options { skipDefaultCheckout() }
      environment {
        HOME = "${env.WORKSPACE}"
        RESULT_FILE = 'apm-agent-benchmark-results.json'
        NODE_VERSION = '14'
      }
      when {
        beforeAgent true
        allOf {
          anyOf {
            branch 'main'
            expression { return params.Run_As_Main_Branch }
            expression { return env.GITHUB_COMMENT?.contains('benchmark tests') }
          }
          expression { return params.bench_ci }
          // todo
          expression {return false }
        }
      }
      steps {
        withGithubNotify(context: 'Benchmarks', tab: 'artifacts') {
          dir(env.BUILD_NUMBER) {
            deleteDir()
            unstash 'source'
            dir(BASE_DIR){
              sh '.ci/scripts/run-benchmarks.sh "${RESULT_FILE}" "${NODE_VERSION}"'
            }
          }
        }
      }
      post {
        always {
          catchError(message: 'sendBenchmarks failed', buildResult: 'FAILURE') {
            sendBenchmarks(file: "${BUILD_NUMBER}/${BASE_DIR}/${RESULT_FILE}",
                           index: 'benchmark-nodejs', archive: true)
          }
          catchError(message: 'deleteDir failed', buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
            deleteDir()
          }
        }
      }
    }
  }
  post {
    cleanup {
      echo "notifyBuildResult()"
    }
  }
}

def generateStep(Map params = [:]){
  def version = params?.version
  def tav = params.containsKey('tav') ? params.tav : ''
  def buildType = params.containsKey('buildType') ? params.buildType : 'release'
  def ELASTIC_APM_ASYNC_HOOKS = String.valueOf(!params.get('disableAsyncHooks', false))
  return {
    withNode(labels: 'linux && immutable', forceWorkspace: true, forceWorker: true) {
      withEnv(["VERSION=${version}", "ELASTIC_APM_ASYNC_HOOKS=${ELASTIC_APM_ASYNC_HOOKS}"]) {
        deleteDir()
        unstash 'source'
        dir("${BASE_DIR}"){
          try {
            retryWithSleep(retries: 2, seconds: 5, backoff: true) {
              sh(label: "Run Tests", script: """.ci/scripts/test.sh -b "${buildType}" -t "${tav}" "${version}" """)
            }
          } catch(e){
            error(e.toString())
          } finally {
            junit(testResults: "test_output/*.junit.xml", allowEmptyResults: true, keepLongStdio: true)
            archiveArtifacts(artifacts: "test_output/*.tap", allowEmptyArchive: true)
          }
        }
      }
    }
  }
}

/**
* Gather the TAV context for the current execution. Then the TAV stage will execute
* the TAV using a smarter approach.
*/
def getSmartTAVContext() {
   context = [:]
   context.ghContextName = 'TAV Test'
   context.ghDescription = context.ghContextName
   context.node = readYaml(file: '.ci/.jenkins_tav_nodejs.yml')

   // Hard to debug what's going on as there are a few nested conditions. Let's then add more verbose output
   echo """\
   env.GITHUB_COMMENT=${env.GITHUB_COMMENT}
   params.Run_As_Main_Branch=${params.Run_As_Main_Branch}
   env.CHANGE_ID=${env.CHANGE_ID}
   env.TAV_UPDATED=${env.TAV_UPDATED}""".stripIndent()

   if (env.GITHUB_COMMENT) {
     def modules = getModulesFromCommentTrigger(regex: 'run module tests for (.+)')
     if (modules.isEmpty()) {
       context.ghDescription = 'TAV Test disabled'
       context.tav = readYaml(text: 'TAV:')
       context.node = readYaml(text: 'NODEJS_VERSION:')
     } else {
       if (modules.find{ it == 'ALL' }) {
         context.tav = readYaml(file: '.ci/.jenkins_tav.yml')
       } else {
         context.ghContextName = 'TAV Test Subset'
         context.ghDescription = 'TAV Test comment-triggered'
         context.tav = readYaml(text: """TAV:${modules.collect{ it.replaceAll('"', '').replaceAll("'", '') }.collect{ "\n  - '${it}'"}.join("") }""")
       }
     }
   } else if (params.Run_As_Main_Branch) {
     context.ghDescription = 'TAV Test param-triggered'
     context.tav = readYaml(file: '.ci/.jenkins_tav.yml')
   } else if (env.CHANGE_ID && env.TAV_UPDATED != "false") {
     context.ghContextName = 'TAV Test Subset'
     context.ghDescription = 'TAV Test changes-triggered'
     sh '.ci/scripts/get_tav.sh .ci/.jenkins_generated_tav.yml'
     context.tav = readYaml(file: '.ci/.jenkins_generated_tav.yml')
   } else {
     context.ghDescription = 'TAV Test disabled'
     context.tav = readYaml(text: 'TAV:')
     context.node = readYaml(text: 'NODEJS_VERSION:')
   }
   return context
 }

 def linting(){
   return {
    withNode(labels: 'linux && immutable', forceWorkspace: true, forceWorker: true) {
      catchError(stageResult: 'UNSTABLE', message: 'Linting failures') {
        withGithubNotify(context: 'Linting') {
          deleteDir()
          unstash 'source'
          docker.image('node:12').inside("-v ${WORKSPACE}/${BASE_DIR}:/app -v /var/lib/jenkins/.git-references/:/var/lib/jenkins/.git-references"){
            withEnv(["HOME=/app"]) {
              sh(label: 'Basic tests I', script: 'cd /app && .ci/scripts/test_basic.sh')
              sh(label: 'Basic tests II', script: 'cd /app && .ci/scripts/test_types_babel_esm.sh')
            }
          }
        }
      }
    }
  }
}

def generateStepForWindows(Map params = [:]){
  def version = params?.version
  def ELASTIC_APM_ASYNC_HOOKS = String.valueOf(!params.get('disableAsyncHooks', false))
  return {
    sh label: 'Prepare services', script: ".ci/scripts/windows/prepare-test.sh ${version}"
    def linuxIp = grabWorkerIP()
    withNode(labels: 'windows-2019-docker-immutable', forceWorkspace: true, forceWorker: true) {
      // When installing with choco the PATH might not be updated within the already connected worker.
      withEnv(["PATH=${PATH};C:\\Program Files\\nodejs",
               "VERSION=${version}",
               "ELASTIC_APM_ASYNC_HOOKS=${ELASTIC_APM_ASYNC_HOOKS}",
               "CASSANDRA_HOST=${linuxIp}",
               "ES_HOST=${linuxIp}",
               "LOCALSTACK_HOST=${linuxIp}",
               "MEMCACHED_HOST=${linuxIp}",
               "MONGODB_HOST=${linuxIp}",
               "MSSQL_HOST=${linuxIp}",
               "MYSQL_HOST=${linuxIp}",
               "PGHOST=${linuxIp}",
               "REDIS_HOST=${linuxIp}"]) {
        try {
          deleteDir()
          unstash 'source'
          dir(BASE_DIR) {
            bat label: 'Ping linux worker', script: "ping -n 3 ${linuxIp}"
            installTools([ [tool: 'nodejs-lts', version: "${version}" ] ])
            bat label: 'Tool versions', script: '''
              npm --version
              node --version
            '''
            retryWithSleep(retries: 2, sideEffect: { bat 'npm cache clean --force' }) {
                bat 'npm install'
            }
            bat 'node test/test.js'
          }
        } catch(e){
          error(e.toString())
        } finally {
          echo 'JUnit archiving no yet in place'
        }
      }
    }

    // If the above execution failed, then it will not reach this section. TBD
    sh label: 'Stop services', script: ".ci/scripts/windows/stop-test.sh ${version}"
  }
}


def grabWorkerIP(){
  def linuxIp = ''
  retryWithSleep(retries: 3, seconds: 5, backoff: true){
    linuxIp = sh(label: 'Get IP', script: '''hostname -I | awk '{print $1}' ''', returnStdout: true)?.trim()
    log(level: 'INFO', text: "Worker IP '${linuxIp}'")
    if(!linuxIp?.trim()){
      error('Unable to get the Linux worker IP')
    }
  }
  return linuxIp
}

/**
* Transform TAG releases from v{major}.{minor}.{patch} to
* ver-{major}-{minor}-{patch}. e.g: given v1.2.3 then
* -ver-1-2-3.
*/
def getVersion() {
  if (env.BRANCH_NAME?.trim() && env.BRANCH_NAME.startsWith('v')) {
    return env.BRANCH_NAME.replaceAll('v', '-ver-').replaceAll('\\.', '-')
  }
  return ''
}

/**
* Calculate the elastic.co release notes URL given the TAG release. Otherwise
* it returns the default current URL.
*/
def getReleaseNotesUrl() {
  def baseUrl = 'https://www.elastic.co/guide/en/apm/agent/nodejs/current'
  if (env.BRANCH_NAME?.trim() && env.BRANCH_NAME.startsWith('v')) {
    def version = env.BRANCH_NAME.replaceAll('v', '')
    def parts = version.split('\\.')
    def major = parts[0]
    return "${baseUrl}/release-notes-${major}.x.html#release-notes-${version}"
  }
  return baseUrl
}

def notifyStatus(def args = [:]) {
  // releaseNotification(slackChannel: "${env.SLACK_CHANNEL}",
  //                     slackColor: args.slackStatus,
  //                     slackCredentialsId: 'jenkins-slack-integration-token',
  //                     to: "${env.NOTIFY_TO}",
  //                     subject: args.subject,
  //                     body: args.body)
}
