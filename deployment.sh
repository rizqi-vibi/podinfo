#!/bin/bash

dockerTag="$1"
namespace="$2"
podReplica="$3"
limitCPU="$4"
limitMemory="$5"
reqCPU="$6"
reqMemory="$7"
ServiceName="$8"
rollbackTag="$9"
yamlResources="kubernetes/${namespace}"
yamlRollback="kubernetes/rollback"
port="9898"
imageUrl="dki-images-registry-vpc.ap-southeast-5.cr.aliyuncs.com/dki/${ServiceName}"
#if [[ $ServiceName == "customer-api" ]]; then
#  shortServiceName="idc.cust"
#elif [[ $ServiceName == "dkisprivyid-api" ]]; then
#  shortServiceName="dkisprivyid"
#else
#  getShortServiceName=$(echo $ServiceName | cut -d '-' -f1)
#  shortServiceName="idc.${getShortServiceName}"
#fi


if [[ ! -d $yamlResources ]]; then
  mkdir -p $yamlResources
else
  rm -rf $yamlResources
  mkdir -p $yamlResources
fi

cp -rf kubernetes/*.yaml $yamlResources

function varsReplace {
    sed -i "s|%{SERVICE_NAME}|${ServiceName}|g" *.yaml
    sed -i "s|%{POD_REPLICA}|${podReplica}|g" *.yaml
    sed -i "s|%{LIMIT_CPU}|${limitCPU}|g" *.yaml
    sed -i "s|%{LIMIT_MEMORY}|${limitMemory}|g" *.yaml
    sed -i "s|%{REQ_CPU}|${reqCPU}|g" *.yaml
    sed -i "s|%{REQ_MEMORY}|${reqMemory}|g" *.yaml
    sed -i "s|%{PORT}|${port}|g" *.yaml
    sed -i "s|%{IMAGE_URL}|${imageUrl}|g" *.yaml
    #sed -i "s|%{SHORT_NAME}|${shortServiceName}|g" *.yaml
    sed -i "s|%{NAMESPACE_KUBE}|${namespace}|g" *.yaml
}

if [[ $namespace == "production" ]]; then
  [[ ! -d $yamlRollback ]] && mkdir -p $yamlRollback
  cp -rf kubernetes/*.yaml $yamlRollback
  (
      cd $yamlRollback
      varsReplace
      sed -i "s|%{TAG}|${rollbackTag}|g" *.yaml
  )
fi

(
    cd $yamlResources
    varsReplace
    sed -i "s|%{TAG}|${dockerTag}|g" *.yaml
)
