#!/bin/bash
PODS=$(kubectl get po -n 5g | grep "ue-" | cut -d " " -f 1)

while read -r podName
do
    echo "Unregistering $podName..."
    # unregister phase
    i=$(echo $podName | cut -d "-" -f 1 | cut -d "e" -f 2)
    IMSI=$(kubectl get configmap -n 5g ue-configmap$i -o yaml | grep 'imsi-' | cut -d ":" -f 2 | cut -d " " -f 2 | tr -d '"')

    clusterIP=$(kubectl get svc webui-service -n 5g --template '{{.spec.clusterIP}}')
    curl http://$clusterIP:5000/api/registered-ue-context -H "Token: admin" > /dev/null
    curl -X DELETE http://$clusterIP:5000/api/subscriber/$IMSI/20893 -H "Token: admin" -d '{"plmnID":"20893","ueId":"$IMSI","AuthenticationSubscription":{"authenticationMethod":"","permanentKey":null,"sequenceNumber":""},"AccessAndMobilitySubscriptionData":{},"SessionManagementSubscriptionData":null,"SmfSelectionSubscriptionData":{},"AmPolicyData":{},"SmPolicyData":{"smPolicySnssaiData":null},"FlowRules":null}' > /dev/null

    echo "Deleting UE$i..."
    helm delete -n 5g ue$i
done < <(echo "$PODS" | tr " " "\n")


