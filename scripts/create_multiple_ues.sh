#!/bin/bash

# This script installs and registers N UEs, it iterates on the values.yaml and installs in the cluster 
# with the "helm install" N UEs command (modifying the values file appropriately)
# For each UE there will be a unique configuration, for example UE-1 will have a UE-configmap1 with unique ISMI
# In each UE an interface called uesimtun0 is created and thanks to it, the UE is connected.  (if the GNB is already deployed)
# Its IP address is decided at runtime (there is a uesubnet parameter in the UPF). 
# So for example the UE4 will have a uesimtun0 with IP address 10.1.0.4 and so on also for the other UEs

N="4" # default value
if [ $# -ne 0 ]
then
  N=$1
fi

N_LEN=${#N}
IMSI_PREFIX="imsi-20893000000"
FORMAT_STR="%"$N_LEN"s"


# Note: if there are 2 UEs in running it means that we start to install from UE3
NUES=$(kubectl get po -n 5g | grep "ue-" | cut -d " " -f 1 | sort -V | cut -d "-" -f 1 | cut -d "e" -f 2 | tail -1) # starting number

echo "Now $N UEs will be registered and installed..."

NUES=$(expr $NUES + 0) # just to not have an error inside the if
for i in $(seq $N); do
  if [ $NUES -ne 0 ]
  then
    i=$(expr $NUES + $i)
  fi
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
  # NOTE: for every new ue we need a related configmap
  echo "Installing UE$i..."
  helm -n 5g install ue$i ../charts/ue --set ue.configmap.name=ue-configmap$i
  
  # NOTE: if you need to run the UE on a particular node of your cluster you can install it like this
  #helm -n 5g install ue$i charts/ue --set ue.configmap.name=ue-configmap$i ue.nodeSelector."kubernetes\.io/hostname"<NAME>"


  sleep 2
done

# the values.yaml file is reset to the default values 
sed -i 's/supi: "'$IMSI'"  # IMSI number/    supi: "imsi-2089300000001"  # IMSI number/g' ../charts/ue/values.yaml 
