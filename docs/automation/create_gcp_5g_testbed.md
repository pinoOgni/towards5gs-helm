# Guide on how to use the 5G testbed on GCP

This guide tries to explain how to configure a 5G testbed on GCP (where the GCP machines have been configured with suitable network configurations). Not all the steps are listed but the most important and also the various reasons for some choices made to make everything works. To understand how everything is setted up, there is a script that starting from 3 machines on GCP, installs everything you need and in the end you will have a 5G testbed with free5gc and UERANSIM installed ready to use.

In this guide there is also a Troubleshooting section useful to understand how to work with the 5G testbed when things are not going well.


  - [Testbed architecture](#testbed-architecture)
  - [Requirements](#requirements)
  - [Set up 5g Testbed](#set-up-5g-testbed)
    - [Interfaces configuration](#interfaces-configuration)
    - [gtp5g kernel module](#gtp5g-kernel-module)
    - [Kubeadm init and join](#kubeadm-init-and-join)
    - [Calico installation](#calico-installation)
    - [Multus installation](#multus-installation)
    - [Persistent Volume](#persistent-volume)
    - [Free5gc installation](#free5gc-installation)
    - [UE registration](#ue-registration)
    - [UERANSIM installation](#ueransim-solution)
    - [Temporary solution](#temporary-solution)
    - [Use the UE](#use-the-ue)
    - [Multiple UEs or multiple GNBs](#multiple-ues-or-multiple-gnbs)
  - [Troubleshooting](#troubleshooting)
    - [One solution to rule them all](#one-solution-to-rule-them-all)
    - [Some pods do not work](#some-pods-do-not-work)
    - [Clean MongoDB](#clean-mongodb)
    - [uesimtun0 created but no connection](#uesimtun0-created-but-no-connection)
    - [uesimtun0 not created](#uesimtun0-not-created)
    - [Promiscuous mode or altname not configured](#promiscuous-mode-or-altname-not-configured)
    - [POD not correctly deployed](#pod-not-correctly-deployed)
    - [MongoDB does not start](#mongodb-does-not-start)

## Testbed architecture

We have 3 nodes:
* master
* worker-1
* worker-2

## Requirements

We need to have installed in all nodes these components: 
* containerd
* runC
* other configurations
* kubeadm
* kubectl
* kubelet
* helm (at least in one node)
* all the packages necessary for the 5G components (in particular the gtp5g module)
* other packages like git gcc g++ cmake autoconf libtool pkg-config libmnl-dev libyaml-dev
* Linux Kernel version 5.8.0. Not mandatory, for the gtp5g kernel module it could be used also the 5.0.0-23-generic.

## Set up 5g Testbed

### Interfaces configuration

We need an interface with one name. We select the `e0` name. This will be used for the free5gc and ueransim installation.
This command must be used on all worker nodes.
```
sudo ip link property add dev ens4 altname e0
``` 
The promiscuous mode must be enabled for master interfaces of MACVLAN interfaces. In fact, allows network interfaces to intercept packets even if the MAC destination address on these packets is different from the MAC address of this interface. This is necesary as MACVLAN interfaces we are using will have diffrent MAC addresses from MAC addresses of their master interfaces.
This command must be used on all worker nodes.

```
sudo ip link set dev e0 promisc on
```

## gtp5g kernel module

We need the gtp5g kernel module on all worker nodes (in reality in this particular solution we know that is will be used only on the worker1 because is there that the UPF will be deployed). This module is used by the UPF pod.

To install it you need the headers so:

```
sudo apt install linux-headers-5.8.0-1039-gcp
git clone -b v0.3.1 https://github.com/free5gc/gtp5g.git
cd gtp5g && make && sudo make install && cd ..
```

## Kubeadm init and join

On the master node we run this command: 
```
sudo kubeadm init --pod-network-cidr=172.22.0.0/16


mkdir -p ~/.kube
sudo cp -i "/etc/kubernetes/admin.conf" ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config
```
In this way we have a fixed version of Kubernetes.
Then on the worker nodes we need to join using the token provided by the kubeadm init command.
If you forgot to take note of the token, or your token has expired (24-hour TTL), you can generate a new token with the following command:

```
sudo kubeadm token create --print-join-command
```
and use the output to join the worker node.
Now you should be have a cluster like that:
```
pino@master:~$ kubectl get nodes
NAME                      STATUS     ROLES           AGE   VERSION
master     NotReady   control-plane   24m   v1.25.0
worker-1   NotReady   <none>          19m   v1.25.0
worker-2   NotReady   <none>          20m   v1.25.0
```

### Calico installation

We install Calico with a custom installation because we need:
  * IPIP mode enabled: to allow the communication pod-to-pod on the GCP network
  * IP forwarding enabled: we need the traffic forwarding enabled because this functionalty is needed by the UPF as it allows him to act as a router.
  * our custom CIDR that is the 172.22.0.0/16 used in the Kubeadm init command
And also we use a fixed version of Calico that is the v3.23.

```
kubectl create -f https://projectcalico.docs.tigera.io/archive/v3.23/manifests/tigera-operator.yaml
curl https://projectcalico.docs.tigera.io/archive/v3.23/manifests/custom-resources.yaml -O
sed -i '/\      nodeSelector: all()/a\   \ containerIPForwarding: "Enabled"' custom-resources.yaml
sed -i 's/192.168.0.0/172.22.0.0/g' custom-resources.yaml
sed -i 's/encapsulation: VXLANCrossSubnet/encapsulation: IPIP/g' custom-resources.yaml
kubectl create -f custom-resources.yaml
```
Now you have a cluster up and running:
```
pino@master:~$ k get nodes
NAME                      STATUS   ROLES           AGE   VERSION
master     Ready    control-plane   52m   v1.25.0
worker-1   Ready    <none>          47m   v1.25.0
worker-2   Ready    <none>          48m   v1.25.0
```

### Multus installation

We need	the Multus-CNI because we need to create more than one interface in pods.
Also in this case we use a fixed version of Multus that is the v3.9.

```
curl https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/v3.9/deployments/multus-daemonset.yml -O
kubectl apply -f multus-daemonset.yml
```

### Persistent Volume

Before the creation of the persistent volume we need to create a folder, for example on `worker-1`
```
pino@worker-1:/pino/ubuntu$ mkdir /pino/ubuntu/pv
```
Then
```
cat << EOF | kubectl apply -f -
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
    path: /pino/ubuntu/pv
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - worker-1
EOF
```

### Free5gc installation

First of all we need to create a namespace where all of the components will be deployed:
```
kubectl create ns 5g
```
Now, to install Free5gc, we use a custom configuration for some values and we use a particular commit for this repo.
We do this on the master node where Helm is installed.
```
git clone https://github.com/Orange-OpenSource/towards5gs-helm.git
cd towards5gs-helm
git checkout cb033169c62883fc9e1ca980a25646579021947a # you can use also the stable version
cd ~
helm -n 5g install free5gc towards5gs-helm/charts/free5gc/ --set global.n2network.masterIf=e0,global.n3network.masterIf=e0,global.n4network.masterIf=e0,global.n6network.masterIf=e0,global.n9network.masterIf=e0,free5gc-upf.upf.nodeSelector."kubernetes\.io/hostname"=worker-1,free5gc-amf.amf.nodeSelector."kubernetes\.io/hostname"=worker-1,free5gc-smf.smf.nodeSelector."kubernetes\.io/hostname"=worker-1,free5gc-ausf.ausf.nodeSelector."kubernetes\.io/hostname"=worker-2,free5gc-nssf.nssf.nodeSelector."kubernetes\.io/hostname"=worker-2,free5gc-udr.udr.nodeSelector."kubernetes\.io/hostname"=worker-2,free5gc-nrf.nrf.nodeSelector."kubernetes\.io/hostname"=worker-2,free5gc-pcf.pcf.nodeSelector."kubernetes\.io/hostname"=worker-2,free5gc-udm.udm.nodeSelector."kubernetes\.io/hostname"=worker-2,free5gc-webui.webui.nodeSelector."kubernetes\.io/hostname"=worker-2
```
Yes, it is a long command but we use the `--set` option with `helm install` with these options because all the PODs with the macvlan need to be on the same node to work properly.

NOTE: you could also need to set:
```
global.n6network.subnetIP=<subnetIP>,global.n6network.cidr=24,global.n6network.gatewayIP=<gatewayIP>,free5gc-upf.upf.n6if.ipAddress=<ipAddress>
```


NOTE about the installation command:
* cidr: this is the cidr of the network of the 3 nodes (24)
* subnetIP: this is the subnet of the network of the 3 nodes (10.0.0.0)
* ipAddressGW: is the gateway of the 3 nodes (10.0.0.1)
* ipAddressNE: is an IP address that does not exists on the network but that is contained in the network (for example 10.0.0.50)



### UE registration

There are two way to register the UE.
  1. Using the WEB-UI (the most used)
  2. Using curl (our implementation that is the fastest)

1. Using the WEB-UI (the most used)
In one terminal inside one node: 
```
kubectl port-forward --namespace 5g svc/webui-service 5000:5000
```
Then in one terminal on your personl host:
```
ssh -L localhost:5000:localhost:5000 gcp-master  # for example gcp-master
```
Now use the web-ui to register the UE with deafult values.
You need to authenticate using admin/free5gc as username/password then you need to click on "Subscribers", then on the "New Subscriber" button and when the form is opened you need to click on "Submit". Please refer to the [Free5GC documentation](https://github.com/free5gc/free5gc/wiki/New-Subscriber-via-webconsole#4-use-browser-to-connect-to-webconsole) for some screenshots.
2. Using curl (our implementation that is the fastest)
If you want to use our implementation, you need to run these commands:
```
clusterIP=$(kubectl get svc webui-service -n 5g --template '{{.spec.clusterIP}}')
curl http://$clusterIP:5000/api/registered-ue-context -H "Token: admin"
curl -X POST http://$clusterIP:5000/api/subscriber/imsi-208930000000003/20893 -H "Token: admin" -d '{"plmnID":"20893","ueId":"imsi-208930000000003","AuthenticationSubscription":{"authenticationManagementField":"8000","authenticationMethod":"5G_AKA","milenage":{"op":{"encryptionAlgorithm":0,"encryptionKey":0,"opValue":""}},"opc":{"encryptionAlgorithm":0,"encryptionKey":0,"opcValue":"8e27b6af0e692e750f32667a3b14605d"},"permanentKey":{"encryptionAlgorithm":0,"encryptionKey":0,"permanentKeyValue":"8baf473f2f8fd09487cccbd7097c6862"},"sequenceNumber":"16f3b3f70fc2"},"AccessAndMobilitySubscriptionData":{"gpsis":["msisdn-0900000000"],"nssai":{"defaultSingleNssais":[{"sst":1,"sd":"010203","isDefault":true},{"sst":1,"sd":"112233","isDefault":true}],"singleNssais":[]},"subscribedUeAmbr":{"downlink":"2 Gbps","uplink":"1 Gbps"}},"SessionManagementSubscriptionData":[{"singleNssai":{"sst":1,"sd":"010203"},"dnnConfigurations":{"internet":{"sscModes":{"defaultSscMode":"SSC_MODE_1","allowedSscModes":["SSC_MODE_2","SSC_MODE_3"]},"pduSessionTypes":{"defaultSessionType":"IPV4","allowedSessionTypes":["IPV4"]},"sessionAmbr":{"uplink":"200 Mbps","downlink":"100 Mbps"},"5gQosProfile":{"5qi":9,"arp":{"priorityLevel":8},"priorityLevel":8}},"internet2":{"sscModes":{"defaultSscMode":"SSC_MODE_1","allowedSscModes":["SSC_MODE_2","SSC_MODE_3"]},"pduSessionTypes":{"defaultSessionType":"IPV4","allowedSessionTypes":["IPV4"]},"sessionAmbr":{"uplink":"200 Mbps","downlink":"100 Mbps"},"5gQosProfile":{"5qi":9,"arp":{"priorityLevel":8},"priorityLevel":8}}}},{"singleNssai":{"sst":1,"sd":"112233"},"dnnConfigurations":{"internet":{"sscModes":{"defaultSscMode":"SSC_MODE_1","allowedSscModes":["SSC_MODE_2","SSC_MODE_3"]},"pduSessionTypes":{"defaultSessionType":"IPV4","allowedSessionTypes":["IPV4"]},"sessionAmbr":{"uplink":"200 Mbps","downlink":"100 Mbps"},"5gQosProfile":{"5qi":9,"arp":{"priorityLevel":8},"priorityLevel":8}},"internet2":{"sscModes":{"defaultSscMode":"SSC_MODE_1","allowedSscModes":["SSC_MODE_2","SSC_MODE_3"]},"pduSessionTypes":{"defaultSessionType":"IPV4","allowedSessionTypes":["IPV4"]},"sessionAmbr":{"uplink":"200 Mbps","downlink":"100 Mbps"},"5gQosProfile":{"5qi":9,"arp":{"priorityLevel":8},"priorityLevel":8}}}}],"SmfSelectionSubscriptionData":{"subscribedSnssaiInfos":{"01010203":{"dnnInfos":[{"dnn":"internet"},{"dnn":"internet2"}]},"01112233":{"dnnInfos":[{"dnn":"internet"},{"dnn":"internet2"}]}}},"AmPolicyData":{"subscCats":["free5gc"]},"SmPolicyData":{"smPolicySnssaiData":{"01010203":{"snssai":{"sst":1,"sd":"010203"},"smPolicyDnnData":{"internet":{"dnn":"internet"},"internet2":{"dnn":"internet2"}}},"01112233":{"snssai":{"sst":1,"sd":"112233"},"smPolicyDnnData":{"internet":{"dnn":"internet"},"internet2":{"dnn":"internet2"}}}}},"FlowRules":[]}'
```

### UERANSIM installation

Just use this command:
```
helm -n 5g install ueransim towards5gs-helm/charts/ueransim --set global.n2network.masterIf=e0,global.n3network.masterIf=e0,ue.nodeSelector."kubernetes\.io/hostname"=worker-1,gnb.nodeSelector."kubernetes\.io/hostname"=worker-1
```

### Temporary solution

This is a temporary solution to overcome the communication problem with Internet. In this way we can use the node where the UE and the UPF are deployed as a server that is contacted by the UE, simulating a real communication.

Motivation: we cannot contact internet from the UE because the GCP network is different from a real (and simple) one and because we have some (right) limitations on how to configure ip addresses on the UPF pod.


The workaround involves removing `n6` ie the macvlan between UPF and the worker node and replacing it with a veth pair. Finally, it is sufficient to configure a routing rule on the node for the return traffic.

NOTE: the node on which to put a head of the veth and configure the routing rules is the one where the UPF pod is running.


### USE the UE

Now you can log in the UE and ping by using the interface uesimtun0:
```
kubectl exec -it -n 5g <ue-pod-name> -- /bin/bash
```
then
```
ping -I uesimutun0 13.13.13.1
```
* Or you can use netcat 
```
kubectl exec -it -n 5g <ue-pod-name> -- /bin/bash
# install netcat ont he ue
apt update && apt install netcat
```
* On the node where the UPF pod is running, run netcat:
```
netcat -l 13.13.13.1 1234
```
* On the UE run netcat
```
netcat 13.13.13.1 1234
HELLO
```

### Multiple UEs or multiple GNBs

You can deploy also multiple GNBs or multiple UEs by using the scripts.

The UE and GNB helm chart are created by the UERANSIM with minor modifications to make everything works fine.




## Troubleshooting

Note: continuously updated.

### One solution to rule them all

While using free5gc and ueransim, various unexpected events can happen. The solution that has worked so far is the following:
1. delete free5gc `helm delete free5gc -n 5g`
2. delete ueransim `helm delete ueransim -n 5g`
3. delete the contents of the folder associated with mongoDB. On worker1 `sudo rm -r /home/ubuntu/pv/*`
4. install free5gc. See Free5gc installation section.
5. register the UE. See UE registration section.
6. install ueransim (actually 5 and 6 can be reversed). See UERANSIM installation section.

If that doesn't work either, then use the `reset` script and then the `create` script. This way the nodes are not only restarted, but everything is reset from the beginning as well. Eventually you will have a working 5G testbed again.


Note: while this solution always works (or almost always), it is useful to understand what can happen and how to fix a problem without having to delete and reinstall everything.


### Some pods do not work

It may happen that some PODs are in the state of `Unknown` or in the state of `Init` or `containerCreating`.This happens when the UERANSIM is deleted and then reinstalled (not always). We have not yet understood what this is due to but we think it is linked to the interfaces with MACVLAN. For more information see this [issue](https://github.com/Orange-OpenSource/towards5gs-helm/issues/55). **In this case, follow the first solution.**


### Clean MongoDB 

According to the Free5GC documentation, you may sometimes need to drop the data stored in the MongoDB. To do so with our implementation, you need simply to empty the folder that was used in the Persistent Volume on the corresponding node.
On worker1:
```
sudo rm -r /home/ubuntu/pv/*
```
Note: If you do not delete the data stored by MongoDB from time to time, even if you delete a subscriber and re-create it, the uesimtun0 interface may not be created.

### uesimtun0 created but no connection

This may occur because of `ipv4.ip_forward` being disabled on the UPF POD. In fact, this functionalty is needed by the UPF as it allows him to act as a router.

To check if it is enabled, run this command on the UPF POD. The result must be 1.
```
cat /proc/sys/net/ipv4/ip_forward
```
Note: if the `create` script was used to create the 5G testbed then Calico was installed with IP forwarding active.

In this particular solution there could be various reasons. You have to check:
1. if interface n6 in the pod still exists
2. if the veth pair has been correctly configured between the UPF and the node where it is executed (worker1)
3. if the routing rules in the node have been set

Note: If the `create` script was used for the creation of the 5G testbed then all these things have been configured. Regarding the routing rules in the node, even when the node is restarted, a `startup` script (in /home/ubuntu/startup.sh) comes into play.

### uesimtun0 not created

There could be various reasons:
1. The UE has not been registered. To do this you need to follow the UE registration section.
2. The UERANSIM has been deleted and installed, all the pods are running but from the UE logs note this error "Cell selection failure, no suitable or acceptable cell found". In this case, follow the first solution.


### Promiscuous mode or altname not configured

If the promiscuos mode or the altname has not been configured correctly, the POD UPF will be in the containerCreating state. To solve this problem we need to go to all worker nodes (in our solution only worker1 would be enough since we know that the UP is there) and execute these commands:
```
sudo ip link property add dev ens4 altname e0
sudo ip link set dev e0 promisc on
```

Note: If the `create` script was used for the creation of the 5G testbed then the promiscuous mode and the altname have been configured and even restarting the node, there is a `startup` script (in /home/ubuntu/startup.sh) that sets everything appropriately when the node is started.

### POD not correctly deployed

To make the testbed work on GCP and face some limitations, we decided to deploy the PODs by choosing the nodes, in particular:
* `amf`, `smf`, `upf`, `gnb` and `ue` run on worker1. All pods running on worker1 are those with macvlan (except the UE which has a point-to-point interface with gnb).
* `ausf`, `nrf`, `nssf`, `pcf`, `udr`, `udm`, `webui` on worker2
* `mongodb` on the node where the folder linked to the PV was created, in this case worker1

Note: in reality the only constraint is precisely on the PODs with MACVLAN since the others communicate using Calico so there are no constraints on where to run them but we fix them on worker2 to have a load balancing

To deal with this problem just run these commands.
Free5gc installation:
```
helm -n 5g install free5gc towards5gs-helm/charts/free5gc/ --set global.n2network.masterIf=e0,global.n3network.masterIf=e0,global.n4network.masterIf=e0,global.n6network.masterIf=e0,global.n9network.masterIf=e0,global.n6network.subnetIP=10.0.0.0,global.n6network.cidr=24,global.n6network.gatewayIP=10.0.0.1,free5gc-upf.upf.n6if.ipAddress=10.0.0.50,free5gc-upf.upf.nodeSelector."kubernetes\.io/hostname"=worker-1,free5gc-amf.amf.nodeSelector."kubernetes\.io/hostname"=worker-1,free5gc-smf.smf.nodeSelector."kubernetes\.io/hostname"=worker-1,free5gc-ausf.ausf.nodeSelector."kubernetes\.io/hostname"=worker-2,free5gc-nssf.nssf.nodeSelector."kubernetes\.io/hostname"=worker-2,free5gc-udr.udr.nodeSelector."kubernetes\.io/hostname"=worker-2,free5gc-nrf.nrf.nodeSelector."kubernetes\.io/hostname"=worker-2,free5gc-pcf.pcf.nodeSelector."kubernetes\.io/hostname"=worker-2,free5gc-udm.udm.nodeSelector."kubernetes\.io/hostname"=worker-2,free5gc-webui.webui.nodeSelector."kubernetes\.io/hostname"=worker-2

```
UERANSIM installation:
```
helm -n 5g install ueransim towards5gs-helm/charts/ueransim --set global.n2network.masterIf=e0,global.n3network.masterIf=e0,ue.nodeSelector."kubernetes\.io/hostname"=worker-1,gnb.nodeSelector."kubernetes\.io/hostname"=worker-1

```


### MongoDB does not start

Probably the pv folder on worker1 has been deleted. If so then:
1. Create the pv folder on worker1 `sudo mkdir /home/ubuntu/pv`
2. Delete the pvc `kubectl delete pvc datadir-mongodb-0 -n 5g` 
3. Delete the pv `kubectl delete pv pv`
4. Create the pv. See Persistent Volume section.
5. Install Free5gc. See Free5gc installation section.