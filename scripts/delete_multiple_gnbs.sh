#!/bin/bash

# This script takes a number N and delete N GNBs (the first N GNBs form kubectl output)
# If N is not passed as an arg value, the script will delete all the GNBs in the cluster (in the 5g namespace)

# Note: in the case where we need to delete N GNBs we need to keep the first one with the service (gnb1)

NGNBS=$(kubectl get po -n 5g | grep "gnb-" | cut -d " " -f 1 | wc -l) # get the number of GNBs pods from 5g namespace


if [ $# -ne 0 ]
then # delete N GNBs
  GNBS=$(kubectl get po -n 5g | grep "gnb-" | grep -v "gnb1-" | cut -d " " -f 1 | head -$1) # remove gnb1 from the list of GNBs to be deleted
fi

if [ $1 -gt $NGNBS ]
then # error
  echo "You cannot delete more GNBs than are running!"
  exit 0
fi

# delete all GNBs where all can means 1
if  [ $# -eq 0 ] ||  [ $NGNBS -eq 1 ]
then
    GNBS=$(kubectl get po -n 5g | grep "gnb-" | cut -d " " -f 1) # get all GNBs pods form 5g namespace
fi


while read -r podName
do

    gnbi=$(echo $podName | cut -d "-" -f 1 | cut -d "e" -f 2)

    echo "Deleting $gnbi..."
    helm delete -n 5g $gnbi
done < <(echo "$GNBS" | tr " " "\n")
