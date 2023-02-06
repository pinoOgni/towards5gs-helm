#!/bin/bash


# if is 0 --> no uesimtun0 is present we use the default interface and make traffic
# using calico, just to simulate a stress test
# if is 1 --> the uesimtun0 is present, we contact the external world (fake in the case of gcp)
# passing through the UPF (UE->GNB->UPF->node1->UPF->GNB->UE)

while :
do
  interface=$(ip -br l | awk '$1 !~ "lo|vir|wl" { print $1}' | grep -w "uesimtun0" | wc -l)
	if [ $interface -eq 0 ]
    then
      echo "Interface uesimtun0 is not created yet" 
    else
      echo "Interface uesimtun0 is available"
      while :
      do
        ping -I uesimtun0 13.13.13.1 -c 40
        sleep 30
      done 
      # break
    fi
	sleep 5
done
