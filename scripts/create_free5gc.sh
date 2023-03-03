#!/bin/bash
if [ "$#" -lt 1 ]; then
  echo "The correct way to use this script is the following:
  ./create_free5gc.sh <shostname-node>

  Example:
  ./create_free5gc.sh worker-1 
    
  "
  exit 1
fi


echo "Installing the free5gc..."
helm -n 5g install --wait free5gc ../charts/free5gc/ --set global.n2network.masterIf=e0,global.n3network.masterIf=e0,global.n4network.masterIf=e0,global.n6network.masterIf=e0,global.n9network.masterIf=e0,free5gc-upf.upf.nodeSelector."kubernetes\.io/hostname"=$1,free5gc-amf.amf.nodeSelector."kubernetes\.io/hostname"=$1,free5gc-smf.smf.nodeSelector."kubernetes\.io/hostname"=$1,free5gc-ausf.ausf.nodeSelector."kubernetes\.io/hostname"=$1,free5gc-nssf.nssf.nodeSelector."kubernetes\.io/hostname"=$1,free5gc-udr.udr.nodeSelector."kubernetes\.io/hostname"=$1,free5gc-nrf.nrf.nodeSelector."kubernetes\.io/hostname"=$1,free5gc-pcf.pcf.nodeSelector."kubernetes\.io/hostname"=$1,free5gc-udm.udm.nodeSelector."kubernetes\.io/hostname"=$1,free5gc-webui.webui.nodeSelector."kubernetes\.io/hostname"=$1