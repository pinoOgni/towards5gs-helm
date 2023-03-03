#!/bin/bash
#
#
# This script creates a custom number of GNBs between 1 and 4
# If you want more GNBs you need to change the CIDR value in the values.yaml file inside the UE chart, then here 
# you need to modify how ip addresss of n2if and n3if are setted for the installation  (maybe TODO pinoOgni)
#
# NOTE: you need to change the hostname used for the nodeselector
#

# Why multiple ip addresses
# The GNB is connected to the AMF via the N2 network and to the UPF via the N3 network (which in the free5gc+ueransim solution are made with the famous MACVLAN bridge)
# To make everything work you need to properly configure the N2 network and the N3 network, there cannot be 2 PODs with the same IP address 
# (if the GNB on N2 has only one IP it is the AMF that goes into error; if the GNB on N3 it has only one IP, the solution works only partially/random behaviour)

MAX=4 # you can modify this value if you change the CIDR (/29) of values.yaml file
N="2" # default number of GNBs to create
X=0 # .250, .251, .252, .253 --> for n2if
Y=4 # .234, .235, .236, .237 --> for n3if

# get number of GNBs to be created
if [ $# -ne 0 ]
then
  N=$1
fi

# first control
if [ $N -gt $MAX ]
then
  echo "The number of GNBs to create cannot is greater than the MAX number of ip address allowed by the CIDR"
  exit 0
fi

# Note: if there are 2 GNBs in running and the CIDR is /29, it means that we can install other 2 GNBs
# So if N+NGNBS is greater than MAX the script exits
NGNBS=$(kubectl get po -n 5g | grep "gnb-" | cut -d " " -f 1 | wc -l) # number of GNBs in running

# second control
tmp=$(expr $N + $NGNBS)
if [ "$tmp" -gt $MAX ]
then
  echo "The number of GNBs to create in addition with the GNBs in running is greater than the MAX number of GNBs that can be installed!"
  exit 0
fi

# Note: if there is only 1 GNB it will be always called gnb1 and if we want to create another 2, 
# we need to create the other GNBs but without the service and also we need to pay attention to the MAX number

NGNBS=$(expr $NGNBS + 0) # just to not have an error inside the if
echo "Now $N GNBs will be installed..."
for i in $(seq $N); do 
  # third control
  if [ $NGNBS -ne 0 ] && [ $i -eq 1 ]  # we start from #NGNBS+1 and we create only gnbs without the service
  then 
   i=$(expr $NGNBS + $i)
   X=$(expr $X + $NGNBS) # is not $NGNBS + 1 because X and Y start from the ip address to use
   Y=$(expr $Y + $NGNBS)
  elif [ $NGNBS -ne 0 ] && [ $i -ne 1 ]
  then
    i=$(expr $NGNBS + $i)
  fi

  # echo "NGNBS $NGNBS; i: $i; X $X, Y $Y\n\n"
  # N=$(printf $FORMAT_STR "$i" | sed 's/ /0/g')

  # change some values in values.yaml file of GNB
  # older solution
  # sed -i 's/.*name: gnb-configmap/    name: gnb-configmap$i/g' ../charts/gnb/values.yaml
  # sed -i 's/.*name: gnb-service/    name: gnb-service$i/g' ../charts/gnb/values.yaml
  
  # install GNB
  # note: for every new gnb we need a related configmap BUT only one service (created with gnb1)


  echo "Installing GNB$i..."
  if [ $i -eq 1 ] 
  then
    helm -n 5g install gnb$i ../charts/gnb --set gnb.configmap.name=gnb-configmap$i,global.n2network.masterIf=e0,global.n3network.masterIf=e0,gnb.nodeSelector."kubernetes\.io/hostname"=energy-b-testbed-worker-1,gnb.n2if.ipAddress=10.100.50.25$X,gnb.n3if.ipAddress=10.100.50.23$Y
  else
    helm -n 5g install gnb$i ../charts/gnb --set gnb.configmap.name=gnb-configmap$i,gnb.createService=false,global.n2network.masterIf=e0,global.n3network.masterIf=e0,gnb.nodeSelector."kubernetes\.io/hostname"=energy-b-testbed-worker-1,gnb.n2if.ipAddress=10.100.50.25$X,gnb.n3if.ipAddress=10.100.50.23$Y
  fi
  let X++
  let Y++
  sleep 2
done
