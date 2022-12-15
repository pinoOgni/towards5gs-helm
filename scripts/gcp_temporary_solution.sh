#!/bin/bash

kubectl exec -i -n 5g $(kubectl get po -n 5g | grep "upf" | cut -d " " -f 1) -- bash -c "ip link del n6"

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

# The routing rule on the upf is configured automatically
# so it remains only to configure a route on the node for the returning traffic

# in this way it can works also for multiple UEs
sudo ip r add 10.1.0.0/24 via 13.13.13.2 dev veth1
