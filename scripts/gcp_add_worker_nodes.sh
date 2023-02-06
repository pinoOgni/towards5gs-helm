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
#   master node: energy-testbed-master
#   worker 1 node: energy-testbed-worker-1
#   worker 2 node: energy-testbed-worker-2
# It also assumes that these are the hostnames
# master node: polito-testbed-tmp-master
# worker 1 node: polito-testbed-tmp-worker-1
# worker 2 node: polito-testbed-tmp-worker-2
# These names will be used as node selector. You can change using yours


echo "
# ==============================================================================================
# Version 1.0.1
# For questions or doubts contact -> Giuseppe Ognibene (pinoOgni)
# Software description: a script to automate addition of worker nodes in a gcp cluster
# ==============================================================================================
"
sleep 5


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

for node in "gcp-1" "gcp-3"; do
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

printf "\033c"
echo "Get the config k8s file from master node..."
config=$(ssh energy-testbed-master  cat "~/.kube/config")

printf "\033c"
echo "Get the token to be used later on worker nodes..."
token=$(ssh gcp-master kubeadm token create --print-join-command)

echo "Kubeadm join on worker gcp-1..."
output_join=$(ssh gcp-1 sudo "$token")

echo "Kubeadm join on worker gcp-3..."
output_join=$(ssh gcp-3 sudo "$token")


echo "Last configurations..."


for node in "gcp-1" "gcp-3"; do
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









