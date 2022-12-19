#!/bin/bash



# This script takes a number N and delete N UEs (the first N UEs from kubectl output)
# If N is not passed as an arg value, the script will delete all the UEs in the cluster (in the 5g namespace)

NUES=$(kubectl get po -n 5g | grep "ue-" | cut -d " " -f 1 | wc -l) # get the number of UEs pods from 5g namespace

if [ $# -ne 0 ]
then # delete N UEs
  UES=$(kubectl get po -n 5g | grep "ue-" | grep -v "ue1-" | cut -d " " -f 1 | sort -V | tail -$1) # remove ue1 from the list of UEs to be deleted
elif [ $# -eq 0 ] && [ $1 -gt $NUES ]
then # error
  echo "You cannot delete more UEs than are running!"
  exit 0
fi

# delete all UEs where all can means 1
if  [ $# -eq 0 ] ||  [ $NUES -eq 1 ]
then
    UES=$(kubectl get po -n 5g | grep "ue-" | cut -d " " -f 1) # get all UEs pods form 5g namespace
fi

while read -r podName
do
    echo "Unregistering $podName..."
    # unregister phase
    i=$(echo $podName | cut -d "-" -f 1 | cut -d "e" -f 2)
    IMSI=$(kubectl get configmap -n 5g ue-configmap$i -o yaml | grep 'imsi-' | cut -d ":" -f 2 | cut -d " " -f 2 | tr -d '"')

    clusterIP=$(kubectl get svc webui-service -n 5g --template '{{.spec.clusterIP}}')
    curl http://$clusterIP:5000/api/registered-ue-context -H "Token: admin" > /dev/null
    curl -X DELETE http://$clusterIP:5000/api/subscriber/$IMSI/20893 -H "Token: admin" -d '{"plmnID":"20893","ueId":"$IMSI","AuthenticationSubscription":{"authenticationMethod":"","permanentKey":null,"sequenceNumber":""},"AccessAndMobilitySubscriptionData":{},"SessionManagementSubscriptionData":null,"SmfSelectionSubscriptionData":{},"AmPolicyData":{},"SmPolicyData":{"smPolicySnssaiData":null},"FlowRules":null}' > /dev/null
done < <(echo "$UES" | tr " " "\n")
