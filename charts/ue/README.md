# UE Helm chart

This is a Helm chart for deploying the UE of the [UERANSIM](https://github.com/aligungr/UERANSIM) project on Kubernetes. It has been tested only with [free5GC](../chart/free5gc) but should also run with [open5gs](https://github.com/open5gs/open5gs).

## Prerequisites
 - A Kubernetes cluster ready to use. You can use [kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/) to create it.
 - [Multus-CNI](https://github.com/intel/multus-cni).
 - [Helm3](https://helm.sh/docs/intro/install/).
 - [Kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) (optional).
 - A physical network interface on each Kubernetes node named `eth0`.
**Note:** If the name of network interfaces on your Kubernetes nodes is different from `eth0`, see [Networks configuration](#networks-configuration).

## Quickstart guide

### NOTE

Before install the UEs, you need to install the GNB component of the UERANSIM. If you need to install only one UE please refer to the UERANSIM chart.

### Register and install multiple UEs
```console
cd scripts
./create_multiple_ue.sh <N>
```
The value of N represents how many UEs you want to install (default 4).

### Check the state of the created pod
```console
kubectl -n <namespace> get pods -l "app=ue"
```

### Unregister and uninstall multiple UEs
```console
cd scripts
./delete_multiple_ue.sh
```

## Configuration

Please refere to [this](../ueransim/README.md) README.

## Reference
 - https://github.com/aligungr/UERANSIM/wiki/

