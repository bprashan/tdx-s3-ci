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
                        sh 'chmod +x tdx_canonical_linux_stack.sh'
                        sh './tdx_canonical_linux_stack.sh --setuptdx'
                    }
                }
            }
        }

        stage('restart tdx host'){
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
                            sh './tdx_canonical_linux_stack.sh --verifytdx'
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
                            sh './tdx_canonical_linux_stack.sh --createtd'
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
                            sh './tdx_canonical_linux_stack.sh --runtdqemu'
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
                            sh './tdx_canonical_linux_stack.sh --runtdlibvirt'
                        }
                    }
                }
            }
        }
    }
}
