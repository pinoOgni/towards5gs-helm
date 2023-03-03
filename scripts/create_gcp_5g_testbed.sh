#!/bin/bash

# Version 1.0.2
# For questions or doubts contact -> Giuseppe Ognibene (pinoOgni)

# set -x
# set -e

if [ "$#" -lt 3 ]; then
  echo "The correct way to use this script is the following:
  ./create_gcp_5g_testbed.sh <ssh-name-master-node> <list-of-ssh-name-worker-nodes>

  Example:
  ./create_gcp_5g_testbed.sh master-node worker-1 worker-2 worker-3 
    
  "
  exit 1
fi


echo "
# ==============================================================================================
# Version 1.0.2
# For questions or doubts contact -> Giuseppe Ognibene (pinoOgni)
# Software description: a script to automate the creation of a 5G testbed on GCP using kubeadm
# The projects used for the 5G part are: free5gc and UERANSIM 
# The cluster is composed by N virtual machines: one master node, N-1 worker nodes
# It uses the helm charts provided by the towards5gs-helm for free5gc and ueransim
# It uses a checkout on a fork of the original repo where we made some changes 
# where there are different scripts like this one

# This script assumes that:
  1. you run it from your local host 
  2. to use it you need to run like that: 
    ./create_gcp_5g_testbed.sh <ssh-name-master-node> <list-of-ssh-name-worker-nodes>
    ./create_gcp_5g_testbed.sh master-node worker-1 worker-2 worker-3 
  3. the OS used is ubuntu
# ==============================================================================================
"

# NOTES
# $1 <ssh-name-master-node>
# $2... <list-of-ssh-name-worker-nodes>
# the first worker node will be used as node reference for the PV


# worker node used for the PV is the first worker node i.e. $2 but we need the hostname and not the ssh-name of your local host
hostname_pv=$(ssh $2 cat /proc/sys/kernel/hostname)
master_node=$1

sleep 5


### Particular notes for this testbed
# We uses a Linux kernel version 5.8.0
# (you could use a new one, it is important that the kernel version works fine ith the gtp5g module)


# loop on master node end worker nodes using ssh node names
for node in "${@:1}"; do
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

# loop on master node end worker nodes using ssh node names
for node in "${@:1}"; do
	ssh $node /bin/bash << 'EOF' 
        # containerd
        echo "Installing containerd..."
        wget https://github.com/containerd/containerd/releases/download/v1.6.2/containerd-1.6.2-linux-amd64.tar.gz
        sudo tar Czxvf /usr/local containerd-1.6.2-linux-amd64.tar.gz
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
        containerd config default | sudo tee /etc/containerd/config.toml
        sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
        sudo systemctl restart containerd
        printf "\033c"


        # cni plugins

        sudo mkdir -p /opt/cni/bin/
        sudo wget https://github.com/containernetworking/plugins/releases/download/v1.1.1/cni-plugins-linux-amd64-v1.1.1.tgz
        sudo tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.1.1.tgz
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


# master node
ssh $master_node /bin/bash << EOF
    # Install helm (at least in one node)
    echo "Installing helm on master node..."
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
config=$(ssh $master_node  cat "~/.kube/config")

# loop worker nodes using ssh node names
for node in "${@:2}"; do
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
token=$(ssh $master_node kubeadm token create --print-join-command)


# loop worker nodes using ssh node names
for node in "${@:2}"; do
    echo "Kubeadm join on worker $node..."
    output_join=$(ssh $node sudo "$token")
done

### Calico and Multus installation

# master node
printf "\033c"
ssh $master_node /bin/bash << EOF
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


# worker node used for the PV is the first worker node i.e. $2
ssh $2 /bin/bash << EXTEOF 
    echo "Creating directory used for the Persistent Volume on the worker-1 node..."
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
          - $hostname_pv
EOF

EXTEOF

printf "\033c"
echo "Now install 5G components and free5gc..."

# master node
ssh $master_node /bin/bash << 'EOF'
    echo "Create a namespace dedicated for 5G..."
    kubectl create ns 5g

    echo "Installing free5gc with our custom configuration..."
    rm -rf towards5gs-helm # in this way we are sure that we are using a clean code

    # new way
    git clone https://github.com/pinoOgni/towards5gs-helm.git
    cd towards5gs-helm
    git checkout pgn/new-ue
    cd ~

EOF

for node in "${@:1}"; do
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


echo "Now you should be able to install free5gc, multiple GNBs/UEs using the scripts changin the value of the node selector with your custom node names"
echo "Then, if you want to ping from inside one UE, you can ping this IP address 13.13.13.1"
echo "But before that you need the free5gc running and you need to run the gcp_temporary_solution script
in the node where the UPF is running."

echo "================ OTHER INFO ================"
echo "kubectl exec -it -n 5g <ue-pod-name> -- /bin/bash"
echo "You can find some useful commands inside the .bashrc file:
* describe-po
* bashenter
* shenter
* logs
To use these commands you need to just type the name of the NF, for example: describe-po upf
"









