# GNB Helm chart

This is a Helm chart for deploying the GNB component of the [UERANSIM](https://github.com/aligungr/UERANSIM) project on Kubernetes. It has been tested only with [free5GC](../chart/free5gc) but should also run with [open5gs](https://github.com/open5gs/open5gs).

## Prerequisites
 - A Kubernetes cluster ready to use. You can use [kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/) to create it.
 - [Multus-CNI](https://github.com/intel/multus-cni).
 - [Helm3](https://helm.sh/docs/intro/install/).
 - [Kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) (optional).
 - A physical network interface on each Kubernetes node named `eth0`.
**Note:** If the name of network interfaces on your Kubernetes nodes is different from `eth0`, see [Networks configuration](#networks-configuration).

## Quickstart guide

### NOTE

This char is only for the GNB component, and it is was created from the UERANSIM chart in case you need one GNB and more UEs (refer to [this](../ue/README.md) README).


### Install GNB
```console
kubectl create ns <namespace>
helm -n <namespace> install <release-name> ./gnb/
```

### Check the state of the created pod
```console
kubectl -n <namespace> get pods -l "app=gnb"
```

### Uninstall GNB
```console
helm -n <namespace> delete <release-name>
```
Or...
```console
helm -n <namespace> uninstall <release-name>
```


## Configuration

Please refere to [this](../ueransim/README.md) README.


## Reference
 - https://github.com/aligungr/UERANSIM/wiki/

