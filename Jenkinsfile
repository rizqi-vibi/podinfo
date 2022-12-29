def doDeployment(def cluster, def dockerVersion, def namespace, def replica, def dkiServiceName, def dockerVersionRollback){
    try{
        sh """        
        chmod +x ./deployment.sh
        if [[ ${namespace} == "production" ]]; then          
          ./deployment.sh ${dockerVersion} ${namespace} ${replica} ${limitCPURelease} ${limitMemoryRelease} ${reqCPURelease} ${reqMemoryRelease} ${dkiServiceName} ${dockerVersionRollback}
        else
          ./deployment.sh ${dockerVersion} ${namespace} ${replica} ${limitCPUAlpha} ${limitMemoryAlpha} ${reqCPUAlpha} ${reqMemoryAlpha} ${dkiServiceName}
        fi
        """
        
        withCredentials([file(credentialsId: "${cluster}", variable: 'kubeconfig')]) {
            sh "kubectl apply -f kubernetes/${namespace}/ -n ${namespace} --kubeconfig=${kubeconfig}"           
        }
        currentBuild.result == "SUCCESS"
    } catch(e){
        currentBuild.result == "FAILURE"
        throw e
    } finally {
        if (currentBuild.result == "FAILURE") {
            echo "Deployment Failure"
        }
    }
}

def pushToRegistry(def dockerVersion){
    try {
        //docker.withRegistry("https://${crUri}", "${crCred}") {
        //    docker.image("${imageName}").push("${dockerVersion}")
        //}
        withCredentials([usernamePassword(credentialsId: 'cr-auth', usernameVariable: 'user', passwordVariable: 'password')]) {
            sh('podman login -u $user -p $password ${registry}')
            sh """            
            podman tag ${imageName} ${imageName}:${dockerVersion}
            podman push ${imageName}:${dockerVersion}            
            """
        }
        currentBuild.result = 'SUCCESS'
    } catch(e) {
        currentBuild.result = 'FAILURE'
        throw e
    } finally {
        if (currentBuild.result == "FAILURE") {
            echo 'FAIL in Push to registry Stage'
        }
    }
}

pipeline {
    agent any

    environment {
        serviceName = "${JOB_NAME}".split('/').first()
        cluster="dkf-cluster"
        crUri = "dki-images-registry-vpc.ap-southeast-5.cr.aliyuncs.com/dki/${serviceName}"
        crCred = "cr-auth"
        registry= "dki-images-registry-vpc.ap-southeast-5.cr.aliyuncs.com"
        imageName = "${crUri}"
        gitRepository = "github.com/kinifinance-dev/${serviceName}.git"
        gitCommitHash = sh(returnStdout: true, script: 'git rev-parse HEAD').trim()
        shortCommitHash = gitCommitHash.take(7)
        // limit Memory and CPU development & staging
        limitMemoryAlpha = "512Mi"
        limitCPUAlpha = "200m"
        reqMemoryAlpha = "64Mi"
        reqCPUAlpha = "100m"
        // limit Memory and CPU Production
        limitMemoryRelease = "512Mi"
        limitCPURelease = "200m"
        reqMemoryRelease = "64Mi"
        reqCPURelease = "100m"
    }
    stages {
        stage ('Build & Preparations') {
            steps {
                script {
                    if (env.GIT_BRANCH.contains("feature") || env.GIT_BRANCH.contains("hotfix") || env.GIT_BRANCH.contains("bugfix") || env.GIT_BRANCH.contains("root")) {
                        env.versioningCode = "sn" // sn = snapshot -> for service_name k8s and versioning
                        env.alphaNS = "development"
                    } else if (env.GIT_BRANCH.contains("master")){
                        env.versioningCode = "rc" // rc = release candidate -> for service_name k8s and versioning
                        env.alphaNS = "staging"
                    } else {
                        echo "environment server not match"
                        currentBuild.result == 'FAILURE'
                    }

                    env.alphaTag = "${versioningCode}-${shortCommitHash}"
                    
                    env.tagCheck = sh (
                        script: "aliyun cr GET /repos/dki-images/${serviceName}/tags/${alphaTag} 2>/dev/null || true",
                        returnStdout: true
                    ).trim()

                    try {
                        if (env.tagCheck.contains("NORMAL")) {
                            echo "skip build, due no changes"
                            env.dockerBuildStatus = 'SKIP'
                        } else {
                            sh """                            
                            buildah bud --layers=true -t ${imageName} --build-arg namespace=${alphaNS} --build-arg serviceNameJson=${serviceName} .
                            """
                            //buildah bud -t ${imageName} --build-arg namespace=${alphaNS} .
                            //docker.build("${imageName}", "--build-arg namespace=${alphaNS} .")
                            //docker build -t ${imageName} --build-arg namespace=${alphaNS} .
                            env.dockerBuildStatus = 'DO_BUILD'
                        }
                        currentBuild.result = 'SUCCESS'
                    } catch(e) {
                        currentBuild.result = 'FAILURE'
                        throw e
                    } finally {
                        if (currentBuild.result == "FAILURE") {
                          echo 'Build Fail'
                        }
                    }
                }
            }

        }
        stage ('Push to Docker Registry') {
            when {
                expression {
                    currentBuild.result == 'SUCCESS' && env.dockerBuildStatus == 'DO_BUILD'
                }
            }
            steps {
                script {
                    pushToRegistry("${alphaTag}")
                }
            }
        }
        stage ('Deployment to Development Environment') {
            when {
                expression {
                    currentBuild.result == 'SUCCESS' && env.alphaNS == 'development'
                }
            }
            steps {
                script {
                    doDeployment("${cluster}", "${alphaTag}", "${alphaNS}", "1", "${serviceName}", "null")
                }
            }
        }
        stage ('Deployment to Staging Environment') {
            when {
                expression {
                    currentBuild.result == 'SUCCESS' && env.alphaNS == 'staging'
                }
            }
            steps {
                script {

                    doDeployment("${cluster}", "${alphaTag}", "${alphaNS}", "1", "${serviceName}", "null")

                    try {
                        timeout(time: 10, unit: 'MINUTES') {
                            env.doDeployProduction = input message: 'Do you want deployment to PRODUCTION ENVIRONMENT?',
                            parameters: [choice(name: 'Production Deployment', choices: 'no\nyes', description: 'Choose "yes" if you want to deploy this build to Production')]
                        }
                        if (userChoice == 'no') {
                            echo "User refuse to deployment this build, stopping...."
                            currentBuild.result = "SUCCESS"
                        }
                    } catch(Throwable e) {
                        echo "Caught ${e.toString()}"
                        currentBuild.result = "SUCCESS"
                    }
                }
            }
        }
        stage ('Deployment to Production Environment') {
            when {
                environment name: 'doDeployProduction', value: 'yes'
            }
            steps {
                script {
                    timeout(time: 10, unit: 'MINUTES') {
                        env.releaseVersion = input (
                             id: 'version', message: 'Input version name, example v1.0.0', parameters: [
                                [$class: 'StringParameterDefinition', description: 'Whatever you type here will be your version', name: 'Version']
                            ]
                        )
                    }

                    env.releaseNS = "production"
                    env.releaseTag = sh (
                        script: "echo \"${alphaTag}\" | sed 's|${versioningCode}|${releaseVersion}|g'",
                        returnStdout: true
                    ).trim()
                    
                    withCredentials([file(credentialsId: "${cluster}", variable: 'kubeconfig')]) {
                        env.rollbackVersionLatest = sh (
                            script: """kubectl get deploy ${serviceName} -n ${releaseNS} -o wide --kubeconfig=${kubeconfig} | awk '{print \$7}' | grep -v 'IMAGES' | cut -d ':' -f2""",
                            returnStdout: true
                        ).trim()
                    }
                   // }
                    withCredentials([usernamePassword(credentialsId: 'cr-auth', usernameVariable: 'user', passwordVariable: 'password')]) {
                        sh('podman login -u $user -p $password ${registry}')
                        sh("podman pull ${crUri}:${alphaTag}")            
                    }

                    env.getIdDockerAlpha= sh (
                      script: """podman images | grep ${alphaTag} | awk '{print \$3}'""",
                      returnStdout: true
                    ).trim()
                    sh """
                        podman tag ${getIdDockerAlpha} ${crUri}:${releaseTag}
                        echo ${rollbackVersionLatest}
                    """
                    pushToRegistry("${releaseTag}")
                    doDeployment("${cluster}", "${releaseTag}", "${releaseNS}", "2", "${serviceName}", "${rollbackVersionLatest}")

                    try {
                        timeout(time: 1, unit: 'DAYS') {
                            env.buildChoice = input message: 'Do you want to tagging / rollback this build?',
                            parameters: [choice(name: 'Action Build', choices: 'Tagging\nRollback Latest\nRollback By Version\nSkip', description: 'Choose the action build')]
                        }
                        if (buildChoice == 'skip') {
                            echo "User refused to action this build, stopping...."
                        }
                    } catch(Throwable e) {
                        echo "Caught ${e.toString()}"
                        currentBuild.result = "SUCCESS"
                    }
                }
            }
        }
        stage('Tagging Release') {
            when {
                environment name: 'buildChoice', value: 'Tagging'
            }
            steps {
                script {                    
                    withCredentials([string(credentialsId: 'github-token', variable: 'TOKEN')]) {                                      
                        sh("git tag -a ${releaseTag} -m 'Release ${releaseTag}'")
                        sh("git push https://${TOKEN}@${gitRepository} --tags")
                    }
                   
                }
            }
        }
        stage('Rollback Latest Deployment') {
            when {
                environment name: 'buildChoice', value: 'Rollback Latest'
            }
            steps {
                script {                    
                    withCredentials([file(credentialsId: "${cluster}", variable: 'kubeconfig')]) {
                        sh "kubectl delete deploy ${serviceName} -n ${releaseNS} --kubeconfig=${kubeconfig}"
                        sh "kubectl apply -f kubernetes/rollback/ -n ${releaseNS} --kubeconfig=${kubeconfig}"
                        //sh "aliyun cr DELETE /repos/dki-images/${serviceName}/tags/${releaseTag}"
                    }
                }
            }
        }
        stage('Rollback By Version') {
            when {
                environment name: 'buildChoice', value: 'Rollback By Version'
            }
            steps {
                script {
                    try {
                      timeout(time: 1, unit: 'DAYS') {
                          env.rollbackVersionInput = input (
                               id: 'version', message: 'Input version name, example v1.0.0-abcdef', parameters: [
                                  [$class: 'StringParameterDefinition', description: 'Whatever you type here will be your version', name: 'Version']
                              ]
                          )
                      }
                    } catch(Exception err) {
                        def user = err.getCauses()[0].getUser()
                        if('SYSTEM' == user.toString()) {
                            echo "timeout reason"
                            currentBuild.result = "FAILURE"
                        } else {
                            echo "Aborted by: [${user}]"
                            currentBuild.result = "SUCCESS"
                        }
                    }
                    sh "sed -i 's|$rollbackVersionLatest|$rollbackVersionInput|g' kubernetes/rollback/deployment.yaml"

                    withCredentials([file(credentialsId: "${cluster}", variable: 'kubeconfig')]) {  
                        sh "kubectl delete deploy ${serviceName} -n ${releaseNS} --kubeconfig=${kubeconfig}"                  
                        sh "kubectl apply -f kubernetes/rollback/ -n ${releaseNS} --kubeconfig=${kubeconfig}"
                        //sh "aliyun cr DELETE /repos/dki-images/${serviceName}/tags/${releaseTag}"
                    }
                }
            }
        }
        stage('Post Build Cleaning Workspace') {
            steps {
                cleanWs()
            }
        }
        
    }
}