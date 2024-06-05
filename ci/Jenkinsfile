def restartNode(node_label){

    node ("$node_label") {
        print "Rebooting $node_label........."
        if (isUnix()) {
            sh "sudo shutdown -r +1"
        } else {
            bat "shutdown /r /f"
        }
    }

    print "Waiting for the $node_label to reboot........."
    sleep(time:80,unit:"SECONDS")

    def numberOfAttemps = 0
    while (numberOfAttemps < 20) {
        if(Jenkins.instance.getNode(node_label).toComputer().isOnline()){
            print "Node $node_label is rebooted and ready to use"
            return true;
        }
        print "Waiting for the $node_label to reboot........."
        sleep(time:30,unit:"SECONDS")
        numberOfAttemps += 1
    }
    print "Node $node_label is not up running"
    return false
}

tdxnode = 'tdx'
workdir = ''
tdx_linux_stack_script = 'tdx_canonical_linux_stack.sh'
isRestartrequired = false

pipeline{
    agent none

    stages{
        stage('setup TDX host'){
            steps{
                node (tdxnode){
                    script{
                        tdxnode = NODE_NAME
                        workdir = pwd()
                        echo "tdxnode: $tdxnode, workspace: $workspace"
                        checkout scm
                        def distro = sh(script: ". /etc/os-release; echo \$NAME", returnStdout: true)
                        echo "system distro: ${distro}"
                        if (distro.contains('CentOS')){
                            tdx_linux_stack_script = 'tdx_centos_linux_stack.sh'
                        }
                        sh "chmod +x $tdx_linux_stack_script"
                        def statusCode = sh(script: "./$tdx_linux_stack_script --setuptdx", returnStatus:true)
                        if (statusCode != 0 ){
                           if(statusCode == 3){
                                echo "Build machine will be restarted..."
                                isRestartrequired = true
                            }else {
                                sh "exit 1"
                            }
                       }
                    }
                }
            }
        }

        stage('restart tdx host'){
            when { expression { return isRestartrequired } }
            steps{
                script{
                    restartNode(tdxnode)
                }
            }
        }

        stage('Verify tdx host'){
            steps{
                node (tdxnode){
                    script{
                        dir ("${workdir}"){
                            sh "./$tdx_linux_stack_script --verifytdx"
                        }
                    }
                }
            }
        }

        stage('Create TD Guest'){
            steps{
                node (tdxnode){
                    script{
                        dir ("${workdir}"){
                            sh "./$tdx_linux_stack_script --createtd"
                        }
                    }
                }
            }
        }

        stage('Run TD Guest with QEMU'){
            steps{
                node (tdxnode){
                    script{
                        dir ("${workdir}"){
                            sh "./$tdx_linux_stack_script --runtdqemu"
                        }
                    }
                }
            }
        }

        stage('Run TD Guest with libvirt'){
            steps{
                node (tdxnode){
                    script{
                        dir ("${workdir}"){
                            sh "./$tdx_linux_stack_script --runtdlibvirt"
                        }
                    }
                }
            }
        }
        stage('Run PyCloudStack Automated Test Suite'){
            steps{
                node (tdxnode){
                    script{
                        dir ("${workdir}"){
                            sh "./$tdx_linux_stack_script --automatedtests"
                        }
                    }
                }
            }
        }
    }
}
