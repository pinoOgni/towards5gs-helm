#!/bin/bash


N="4"
if [ $# -ne 0 ]
then
  N=$1
fi

N_LEN=${#N}
IMSI_PREFIX="imsi-20893000000"
FORMAT_STR="%"$N_LEN"s"

echo "Now $N UEs will be registered and installed..."
for i in $(seq $N); do
  N=$(printf $FORMAT_STR "$i" | sed 's/ /0/g')
  IMSI="$IMSI_PREFIX$N"
  echo $IMSI

  # registration phase
  echo "Registering UE$i..."
  clusterIP=$(kubectl get svc webui-service -n 5g --template '{{.spec.clusterIP}}')
  curl http://$clusterIP:5000/api/registered-ue-context -H "Token: admin" > /dev/null
  curl -X POST http://$clusterIP:5000/api/subscriber/$IMSI/20893 -H "Token: admin" -d '{"plmnID":"20893","ueId":"$IMSI","AuthenticationSubscription":{"authenticationManagementField":"8000","authenticationMethod":"5G_AKA","milenage":{"op":{"encryptionAlgorithm":0,"encryptionKey":0,"opValue":""}},"opc":{"encryptionAlgorithm":0,"encryptionKey":0,"opcValue":"8e27b6af0e692e750f32667a3b14605d"},"permanentKey":{"encryptionAlgorithm":0,"encryptionKey":0,"permanentKeyValue":"8baf473f2f8fd09487cccbd7097c6862"},"sequenceNumber":"16f3b3f70fc2"},"AccessAndMobilitySubscriptionData":{"gpsis":["msisdn-0900000000"],"nssai":{"defaultSingleNssais":[{"sst":1,"sd":"010203","isDefault":true},{"sst":1,"sd":"112233","isDefault":true}],"singleNssais":[]},"subscribedUeAmbr":{"downlink":"2 Gbps","uplink":"1 Gbps"}},"SessionManagementSubscriptionData":[{"singleNssai":{"sst":1,"sd":"010203"},"dnnConfigurations":{"internet":{"sscModes":{"defaultSscMode":"SSC_MODE_1","allowedSscModes":["SSC_MODE_2","SSC_MODE_3"]},"pduSessionTypes":{"defaultSessionType":"IPV4","allowedSessionTypes":["IPV4"]},"sessionAmbr":{"uplink":"200 Mbps","downlink":"100 Mbps"},"5gQosProfile":{"5qi":9,"arp":{"priorityLevel":8},"priorityLevel":8}},"internet2":{"sscModes":{"defaultSscMode":"SSC_MODE_1","allowedSscModes":["SSC_MODE_2","SSC_MODE_3"]},"pduSessionTypes":{"defaultSessionType":"IPV4","allowedSessionTypes":["IPV4"]},"sessionAmbr":{"uplink":"200 Mbps","downlink":"100 Mbps"},"5gQosProfile":{"5qi":9,"arp":{"priorityLevel":8},"priorityLevel":8}}}},{"singleNssai":{"sst":1,"sd":"112233"},"dnnConfigurations":{"internet":{"sscModes":{"defaultSscMode":"SSC_MODE_1","allowedSscModes":["SSC_MODE_2","SSC_MODE_3"]},"pduSessionTypes":{"defaultSessionType":"IPV4","allowedSessionTypes":["IPV4"]},"sessionAmbr":{"uplink":"200 Mbps","downlink":"100 Mbps"},"5gQosProfile":{"5qi":9,"arp":{"priorityLevel":8},"priorityLevel":8}},"internet2":{"sscModes":{"defaultSscMode":"SSC_MODE_1","allowedSscModes":["SSC_MODE_2","SSC_MODE_3"]},"pduSessionTypes":{"defaultSessionType":"IPV4","allowedSessionTypes":["IPV4"]},"sessionAmbr":{"uplink":"200 Mbps","downlink":"100 Mbps"},"5gQosProfile":{"5qi":9,"arp":{"priorityLevel":8},"priorityLevel":8}}}}],"SmfSelectionSubscriptionData":{"subscribedSnssaiInfos":{"01010203":{"dnnInfos":[{"dnn":"internet"},{"dnn":"internet2"}]},"01112233":{"dnnInfos":[{"dnn":"internet"},{"dnn":"internet2"}]}}},"AmPolicyData":{"subscCats":["free5gc"]},"SmPolicyData":{"smPolicySnssaiData":{"01010203":{"snssai":{"sst":1,"sd":"010203"},"smPolicyDnnData":{"internet":{"dnn":"internet"},"internet2":{"dnn":"internet2"}}},"01112233":{"snssai":{"sst":1,"sd":"112233"},"smPolicyDnnData":{"internet":{"dnn":"internet"},"internet2":{"dnn":"internet2"}}}}},"FlowRules":[]}' > /dev/null


  # change imsi value in values.yaml file of UE
  sed -i 's/.*IMSI number/    supi: "'$IMSI'"  # IMSI number/g' ../charts/ue/values.yaml
  
  # install UEi
  # note: for every new ue we need a related configmap
  echo "Installing UE$i..."
  helm -n 5g install ue$i ../charts/ue --set ue.configmap.name=ue-configmap$i
  
  # note: if you need to run the UE on a particular node of your cluster you can install it like this
  #helm -n 5g install ue$i charts/ue --set ue.configmap.name=ue-configmap$i ue.nodeSelector."kubernetes\.io/hostname"<NAME>"


  sleep 2
done

# the values.yaml file is reset to the default values 
sed -i 's/supi: "'$IMSI'"  # IMSI number/    supi: "imsi-2089300000001"  # IMSI number/g' ../charts/ue/values.yaml 