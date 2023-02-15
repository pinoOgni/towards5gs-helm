#!/bin/bash

# Version 1.0.1
# For questions or doubts contact -> Giuseppe Ognibene (pinoOgni)
# Software description: a script to automate the creation of a 5G testbed on GCP using kubeadm
# The projects used for the 5G part are: free5gc and UERANSIM
# The cluster is composed by 3 virtual machines: one master node, two worker nodes
# It uses the helm charts provided by the towards5gs-helm for free5gc and ueransim
# It uses a checkout on a fork of the original repo where we made some changes

#   TODO --> WE USE A TEMPORARY SOLUTION
#################################
# There is a problem with the connection between the UE and Internet. 
# The interface uesimtun0 inside the UE pod is created but if you try to reach internet, it does not work.
# This problem is related to the GCP network and also to the impossibility to set particular IP addresses 
# on the installation phase of the UPF pod of the free5gc project
#
#################################

# set -x
# set -e

# This script assume that you run it from your local host and that you have the following aliases on the 
# config file inside the .ssh directory
#   master node: gcp-master
#   worker 1 node: gcp-1
#   worker 2 node: gcp-2
# It also assumes that these are the hostnames
# master node: polito-testbed-tmp-master
# worker 1 node: polito-testbed-tmp-worker-1
# worker 2 node: polito-testbed-tmp-worker-2
# These names will be used as node selector. You can change using yours


echo "
# ==============================================================================================
# Version 1.0.1
# For questions or doubts contact -> Giuseppe Ognibene (pinoOgni)
# Software description: a script to automate the creation of a 5G testbed on GCP using kubeadm
# The projects used for the 5G part are: free5gc and UERANSIM
# The cluster is composed by 3 virtual machines: one master node, two worker nodes
# It uses the helm charts provided by the towards5gs-helm for free5gc and ueransim
# It uses a checkout on a fork of the original repo where we made some changes
# ==============================================================================================
"
sleep 5


### Particular notes for this testbed
# We uses a Linux kernel version 5.8.0 (you could use a new one, it is important that the kernel version works fine ith the gtp5g module)

for node in "gcp-master" "gcp-1" "gcp-2"; do
    echo "Downgrade kernel on node $node..."
	ssh $node /bin/bash << EOF 
        sudo apt install -y linux-image-unsigned-5.8.0-1039-gcp
        # TODO (pinoOgni) this works fine but when the machine is rebooted another kernel version is used again
        sudo sed -i 's/GRUB_DEFAULT.*/GRUB_DEFAULT="Advanced options for Ubuntu 20.04.5 LTS (20.04) (on \/dev\/sda1)>Ubuntu, with Linux 5.8.0-1039-gcp (on \/dev\/sda1)"/g' /etc/default/grub.d/50-cloudimg-settings.cfg
        sudo update-grub2
        sudo reboot
EOF
done

echo "
# Now we need to wait for the reboot of the 3 nodes, then we can procede to install all the components needed and then...
# ==============================================================================================
# Preliminary requirements: we need to install  in all nodes these components and set some network configurations: 
# containerd, runC, kubeadm, kubectl, kubelet, gtp5g module(worker nodes), helm (at least in  one node)
# linux headers, altname e0 and promiscuous mode on
# ==============================================================================================
"
sleep 60



### Preliminary requirements
# We need to install  in all nodes these components and set some network configurations: 
# * containerd
# * runC
# * some network configurations
# * kubeadm
# * kubectl
# * kubelet
# * other packages
# * all the packages necessary for the 5G components (in particular the gtp5g module)

for node in "gcp-master" "gcp-1" "gcp-2"; do
	ssh $node /bin/bash << 'EOF' 
        # containerd
        echo "Installing containerd..."
		wget https://github.com/containerd/containerd/releases/download/v1.5.5/containerd-1.5.5-linux-amd64.tar.gz
		sudo tar Czxvf /usr/local containerd-1.5.5-linux-amd64.tar.gz
		wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
		sudo mv containerd.service /usr/lib/systemd/system/
		sudo systemctl daemon-reload
		sudo systemctl enable --now containerd
        printf "\033c"
        # runC
        echo "Installing runC..."
		wget https://github.com/opencontainers/runc/releases/download/v1.1.1/runc.amd64
		sudo install -m 755 runc.amd64 /usr/local/sbin/runc
		sudo mkdir -p /etc/containerd/
		sudo containerd config default | sudo tee /etc/containerd/config.toml
		sudo systemctl restart containerd
        printf "\033c"
        # network configurations
        echo "Configuring network configurations..."
		sudo modprobe overlay
		sudo modprobe br_netfilter
sudo bash -c 'cat << EOF | sudo tee /etc/sysctl.d/k8s.conf
            net.bridge.bridge-nf-call-iptables  = 1
            net.ipv4.ip_forward                 = 1
            net.bridge.bridge-nf-call-ip6tables = 1
EOF'  # solution to overcome some problemds with intent
		sudo sysctl --system
		# sudo bash -c "echo 1 > /proc/sys/net/ipv4/ip_forward" ## not on gcp because it must be enabled from the gcp console
        printf "\033c"
        # kubeadm, kubectl, kubelet
        echo "Installing kubeadm, kubectl, kubelet...."
		sudo apt-get update && sudo apt-get install -y apt-transport-https curl
        curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
        sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
        sudo apt-get install -y --allow-change-held-packages --allow-downgrades kubelet=1.23.8-00 kubectl=1.23.3-00 kubeadm=1.23.8-00
        sudo apt-mark hold kubelet kubeadm kubectl
        
        # sudo apt-get install libelf-dev  # for bpftool
        printf "\033c"
        echo "Installing other components used later like gcc, cmake..."
        sudo apt -y update
        sudo apt -y install git gcc g++ cmake autoconf libtool pkg-config libmnl-dev libyaml-dev
        printf "\033c"
        echo "Installing gtp5g module..."
        sudo apt install -y linux-headers-5.8.0-1039-gcp
        rm -rf gtp5g # in this way we are sure that we are using a clean code
        git clone -b v0.3.1 https://github.com/free5gc/gtp5g.git
        cd gtp5g && make && sudo make install && cd ..

        echo "Setting some custom parameters on network interfaces..."
        sudo ip link property add dev ens4 altname e0
        sudo ip link set dev e0 promisc on
        printf "\033c"

        # Create a startup file bash: in this way even if the node is rebooted altname and promiscuos mode are setted
        echo "Create a startup file bash fr altname, promiscuos mode..."
        sudo rm /home/ubuntu/startup.sh # for safety
        sudo touch /home/ubuntu/startup.sh
        sudo bash -c 'echo "#!/bin/bash" >> /home/ubuntu/startup.sh'
        sudo bash -c 'echo "sudo ip link property add dev ens4 altname e0" >> /home/ubuntu/startup.sh'
        sudo bash -c 'echo "sudo ip link set dev e0 promisc on" >> /home/ubuntu/startup.sh'
        sudo chmod +x /home/ubuntu/startup.sh
        crontab -l | { cat; echo "@reboot /home/ubuntu/startup.sh"; } | crontab -  
        echo "Do not worry about 'no cronotab for <user>' it is ok" 
EOF
done

printf "\033c"
echo "Now we can create the K8s cluster..."
sleep 10


ssh gcp-master /bin/bash << EOF
    # Install helm (at least in one node)
    echo "Installing helm on gcp-master node..."
	curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
	chmod 700 get_helm.sh
	./get_helm.sh

    # Kubeadm init
    echo "Kubeadm init on master node..."
    sudo kubeadm init --kubernetes-version=1.23.8 --pod-network-cidr=172.22.0.0/16
    rm -rf .kube # for safety
    mkdir -p ~/.kube
    sudo cp -i "/etc/kubernetes/admin.conf" ~/.kube/config
    sudo chown "$(id -u):$(id -g)" ~/.kube/config
    sudo chown -R \$USER \$HOME/.kube # for safey. Note: we need to escape the $
EOF

printf "\033c"
echo "Get the config k8s file from master node..."
config=$(ssh gcp-master  cat "~/.kube/config")

for node in "gcp-1" "gcp-2"; do
    echo "Create config k8s file in node $node..."
    ssh $node /bin/bash << EOF 
        rm -rf .kube # for safety
        mkdir -p ~/.kube
        cd ~/.kube
        touch config
        echo "$config" > config
        sudo chown -R \$USER \$HOME/.kube  # for safey. Note: we need to escape the $
EOF
done

printf "\033c"
echo "Get the token to be used later on worker nodes..."
token=$(ssh gcp-master kubeadm token create --print-join-command)

echo "Kubeadm join on worker gcp-1..."
output_join=$(ssh gcp-1 sudo "$token")

echo "Kubeadm join on worker gcp-2..."
output_join=$(ssh gcp-2 sudo "$token")


### Calico and Multus installation

printf "\033c"
ssh gcp-master /bin/bash << EOF
    echo "Calico installation with custom configuration..."
    kubectl create -f https://projectcalico.docs.tigera.io/archive/v3.23/manifests/tigera-operator.yaml
    curl https://projectcalico.docs.tigera.io/archive/v3.23/manifests/custom-resources.yaml -O
    sed -i '/\      nodeSelector: all()/a\   \ containerIPForwarding: "Enabled"' custom-resources.yaml
    sed -i 's/192.168.0.0/172.22.0.0/g' custom-resources.yaml
    # the IPIP mode is used only for gcp cluster
    sed -i 's/encapsulation: VXLANCrossSubnet/encapsulation: IPIP/g' custom-resources.yaml  
    kubectl apply -f custom-resources.yaml
    echo "Waiting Calico pods to be running..."
    kubectl wait pods --all -n calico-system --for condition=Ready
    echo "Multus installation..."
    curl https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/v3.9/deployments/multus-daemonset.yml -O
    kubectl apply -f multus-daemonset.yml
    echo "Waiting Multus pods to be running..."
    kubectl wait pods --all -n kube-system --for condition=Ready
EOF

printf "\033c"

# Directory ad relative persistent volume used by mongodb (pod of free5gc)
ssh gcp-1 /bin/bash << EXTEOF 
    echo "Creating directory used for the Persistent Volume on the gcp-1 node..."
    sudo rm -rf /home/ubuntu/pv
    sudo mkdir -p /home/ubuntu/pv

    echo "Creating the Persistent Volume named pv inside the 5g namespace..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv
  labels:
    project: free5gc
spec:
  capacity:
    storage: 8Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  local:
    path: /home/ubuntu/pv
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - polito-testbed-tmp-worker-1
EOF

EXTEOF

printf "\033c"
echo "Now install 5G components and free5gc..."

ssh gcp-master /bin/bash << 'EOF'
    echo "Create a namespace dedicated for 5G..."
    kubectl create ns 5g

    echo "Installing free5gc with our custom configuration..."
    rm -rf towards5gs-helm # in this way we are sure that we are using a clean code

    # old way
    # git clone https://github.com/Orange-OpenSource/towards5gs-helm.git
    # cd towards5gs-helm
    # git checkout cb033169c62883fc9e1ca980a25646579021947a
    
    # new way
    git clone https://github.com/pinoOgni/towards5gs-helm.git
    cd towards5gs-helm
    git checkout pgn/gcp
    cd ~

    echo "Installing free5gc and waiting Free5gc pods to be running.."
    helm -n 5g install --wait free5gc towards5gs-helm/charts/free5gc/ --set global.n2network.masterIf=e0,global.n3network.masterIf=e0,global.n4network.masterIf=e0,global.n6network.masterIf=e0,global.n9network.masterIf=e0,free5gc-upf.upf.nodeSelector."kubernetes\.io/hostname"=polito-testbed-tmp-worker-1,free5gc-amf.amf.nodeSelector."kubernetes\.io/hostname"=polito-testbed-tmp-worker-1,free5gc-smf.smf.nodeSelector."kubernetes\.io/hostname"=polito-testbed-tmp-worker-1,free5gc-ausf.ausf.nodeSelector."kubernetes\.io/hostname"=polito-testbed-tmp-worker-2,free5gc-nssf.nssf.nodeSelector."kubernetes\.io/hostname"=polito-testbed-tmp-worker-2,free5gc-udr.udr.nodeSelector."kubernetes\.io/hostname"=polito-testbed-tmp-worker-2,free5gc-nrf.nrf.nodeSelector."kubernetes\.io/hostname"=polito-testbed-tmp-worker-2,free5gc-pcf.pcf.nodeSelector."kubernetes\.io/hostname"=polito-testbed-tmp-worker-2,free5gc-udm.udm.nodeSelector."kubernetes\.io/hostname"=polito-testbed-tmp-worker-2,free5gc-webui.webui.nodeSelector."kubernetes\.io/hostname"=polito-testbed-tmp-worker-2

    # kubectl wait pods --all -n 5g --for condition=Ready
    
    printf "\033c"


    # THE UERANSIM INSTALLATION IS DELETED: because you may want to install multiple UEs and multiple GNBs with the appropriated scripts
    # registration phase
    # echo "Registering the UE..."
    # clusterIP=$(kubectl get svc webui-service -n 5g --template '{{.spec.clusterIP}}')
    # curl http://$clusterIP:5000/api/registered-ue-context -H "Token: admin"
    # curl -X POST http://$clusterIP:5000/api/subscriber/imsi-208930000000003/20893 -H "Token: admin" -d '{"plmnID":"20893","ueId":"imsi-208930000000003","AuthenticationSubscription":{"authenticationManagementField":"8000","authenticationMethod":"5G_AKA","milenage":{"op":{"encryptionAlgorithm":0,"encryptionKey":0,"opValue":""}},"opc":{"encryptionAlgorithm":0,"encryptionKey":0,"opcValue":"8e27b6af0e692e750f32667a3b14605d"},"permanentKey":{"encryptionAlgorithm":0,"encryptionKey":0,"permanentKeyValue":"8baf473f2f8fd09487cccbd7097c6862"},"sequenceNumber":"16f3b3f70fc2"},"AccessAndMobilitySubscriptionData":{"gpsis":["msisdn-0900000000"],"nssai":{"defaultSingleNssais":[{"sst":1,"sd":"010203","isDefault":true},{"sst":1,"sd":"112233","isDefault":true}],"singleNssais":[]},"subscribedUeAmbr":{"downlink":"2 Gbps","uplink":"1 Gbps"}},"SessionManagementSubscriptionData":[{"singleNssai":{"sst":1,"sd":"010203"},"dnnConfigurations":{"internet":{"sscModes":{"defaultSscMode":"SSC_MODE_1","allowedSscModes":["SSC_MODE_2","SSC_MODE_3"]},"pduSessionTypes":{"defaultSessionType":"IPV4","allowedSessionTypes":["IPV4"]},"sessionAmbr":{"uplink":"200 Mbps","downlink":"100 Mbps"},"5gQosProfile":{"5qi":9,"arp":{"priorityLevel":8},"priorityLevel":8}},"internet2":{"sscModes":{"defaultSscMode":"SSC_MODE_1","allowedSscModes":["SSC_MODE_2","SSC_MODE_3"]},"pduSessionTypes":{"defaultSessionType":"IPV4","allowedSessionTypes":["IPV4"]},"sessionAmbr":{"uplink":"200 Mbps","downlink":"100 Mbps"},"5gQosProfile":{"5qi":9,"arp":{"priorityLevel":8},"priorityLevel":8}}}},{"singleNssai":{"sst":1,"sd":"112233"},"dnnConfigurations":{"internet":{"sscModes":{"defaultSscMode":"SSC_MODE_1","allowedSscModes":["SSC_MODE_2","SSC_MODE_3"]},"pduSessionTypes":{"defaultSessionType":"IPV4","allowedSessionTypes":["IPV4"]},"sessionAmbr":{"uplink":"200 Mbps","downlink":"100 Mbps"},"5gQosProfile":{"5qi":9,"arp":{"priorityLevel":8},"priorityLevel":8}},"internet2":{"sscModes":{"defaultSscMode":"SSC_MODE_1","allowedSscModes":["SSC_MODE_2","SSC_MODE_3"]},"pduSessionTypes":{"defaultSessionType":"IPV4","allowedSessionTypes":["IPV4"]},"sessionAmbr":{"uplink":"200 Mbps","downlink":"100 Mbps"},"5gQosProfile":{"5qi":9,"arp":{"priorityLevel":8},"priorityLevel":8}}}}],"SmfSelectionSubscriptionData":{"subscribedSnssaiInfos":{"01010203":{"dnnInfos":[{"dnn":"internet"},{"dnn":"internet2"}]},"01112233":{"dnnInfos":[{"dnn":"internet"},{"dnn":"internet2"}]}}},"AmPolicyData":{"subscCats":["free5gc"]},"SmPolicyData":{"smPolicySnssaiData":{"01010203":{"snssai":{"sst":1,"sd":"010203"},"smPolicyDnnData":{"internet":{"dnn":"internet"},"internet2":{"dnn":"internet2"}}},"01112233":{"snssai":{"sst":1,"sd":"112233"},"smPolicyDnnData":{"internet":{"dnn":"internet"},"internet2":{"dnn":"internet2"}}}}},"FlowRules":[]}'
    # printf "\033c"
    # install UERANSIM
    # helm -n 5g install --wait ueransim towards5gs-helm/charts/ueransim --set global.n2network.masterIf=e0,global.n3network.masterIf=e0,ue.nodeSelector."kubernetes\.io/hostname"=polito-testbed-tmp-worker-1,gnb.nodeSelector."kubernetes\.io/hostname"=polito-testbed-tmp-worker-1

    printf "\033c"
    # FIRST PART OF THE TEMPORARY SOLUTION
    echo "Temporary solution to allow UE to work..."
    echo "Remove the n6 interface from the upf..."
    kubectl exec -i -n 5g $(kubectl get po -n 5g | grep "upf" | cut -d " " -f 1) -- bash -c "ip link del n6"
EOF


ssh gcp-1 /bin/bash << 'EOF'
    # SECOND PART OF THE TEMPORARY SOLUTION
    # On the node where the upf is deployed (worker1) add a veth pair
    sudo ip link del veth1 # remove possible old veth1
    sudo ip link add veth1 type veth peer name veth1_ 

    # We need to obtain the network namespace of the upf by following this procedure
    echo "We need to obtain the network namespace of the upf by following this procedure"
    podName=$(kubectl get po -n 5g | grep "upf" | cut -d " " -f 1)
    echo "podname $podName"
    containerID=$(kubectl get po -n 5g $podName -o yaml | grep -m2 containerID | tail -n1 | cut -d '/' -f 3)
    echo "containerID $containerID"
    pid=$(sudo crictl inspect $containerID | grep /ns/net | sed -e 's/\"path\": \"\/proc\/\(.*\)\/ns\/net\"/\1/')
    echo "pid $pid"
    netnsname=$(sudo ip netns identify $pid)
    echo "netnsname $netnsname"
    echo "Do not worry about the Error/Warning before..."
    sudo ip link set veth1_ netns $netnsname
    sudo ip link set dev veth1 up
    sudo ip netns exec $netnsname ip link set dev veth1_ up
    sudo ip addr add 13.13.13.1/24 dev veth1
    sudo ip netns exec $netnsname ip addr add 13.13.13.2/24 dev veth1_ 

    #  The routing rule on the upf is configured automatically
    # so it remains only to configure a route on the node for the returning traffic

    sudo ip r add 10.1.0.0/24 via 13.13.13.2 dev veth1



    # same procedure as before but saved in a script for the startup.sh script
    sudo bash -c 'echo "sudo ip link add veth1 type veth peer name veth1_" >> /home/ubuntu/startup.sh'
    sudo bash -c 'echo "podName=\$(kubectl get po -n 5g | grep "upf" | cut -d " " -f 1)" >> /home/ubuntu/startup.sh'
    sudo bash -c 'echo "containerID=\$(kubectl get po -n 5g \$podName -o yaml | grep -m2 containerID | tail -n1 | cut -d '/' -f 3)" >> /home/ubuntu/startup.sh'
    sudo bash -c 'echo "pid=\$(sudo crictl inspect \$containerID | grep /ns/net)" >> /home/ubuntu/startup.sh'
    sudo bash -c 'echo "netnsname=\$(sudo ip netns identify \$pid)" >> /home/ubuntu/startup.sh'
    sudo bash -c 'echo "sudo ip link set dev veth1_ netns $netnsname" >> /home/ubuntu/startup.sh'
    sudo bash -c 'echo "sudo ip link set dev veth1 up" >> /home/ubuntu/startup.sh'
    sudo bash -c 'echo "sudo ip netns exec $netnsname ip link set dev veth1_ up" >> /home/ubuntu/startup.sh'
    sudo bash -c 'echo "sudo ip addr add 13.13.13.1/24 dev veth1" >> /home/ubuntu/startup.sh'
    sudo bash -c 'echo "sudo ip netns exec $netnsname ip addr add 13.13.13.2/24 dev veth1_" >> /home/ubuntu/startup.sh'
    sudo bash -c 'echo "sudo ip r add 10.1.0.0/24 via 13.13.13.2 dev veth1" >> /home/ubuntu/startup.sh'
EOF


echo "Last configurations..."


for node in "gcp-master" "gcp-1" "gcp-2"; do
    ssh $node /bin/bash << 'EOF' 
    if grep -q -m1 bashenter .bashrc; then
        echo "Functions already present in the node..."
    else
    echo "Adding functions to the node..."
	cat >> .bashrc <<'EOL'

function shenter() {
        podName=$(kubectl get po -n 5g | grep "$1" | cut -d " " -f 1)
        kubectl exec -it -n 5g $podName -- sh
}

function bashenter() {
	podName=$(kubectl get po -n 5g | grep "$1" | cut -d " " -f 1)
	kubectl exec -it -n 5g $podName -- bash
}

function logs() {
	kubectl logs -f -n 5g $(kubectl get po -n 5g | grep "$1" | cut -d " " -f 1)
}

function describe-po() {
        kubectl describe po -n 5g $(kubectl get po -n 5g | grep "$1" | cut -d " " -f 1)
}

alias k="kubectl"
EOL
source ~/.bashrc
fi
EOF
done


echo "Now you should be able to register the UE and install UERANSIM or install multiple GNBs/UEs using the scripts"
echo "Then, from inside one UE, you can ping this IP address 13.13.13.1"
echo "kubectl exec -it -n 5g <ue-pod-name> -- /bin/bash"
echo "You can find some useful commands inside the .bashrc file:
* describe-po
* bashenter
* shenter
* logs
To use these commands you need to just type the name of the NF, for example: describe-po upf
"









