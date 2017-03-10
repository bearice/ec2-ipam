#!/bin/bash

function get_metadata {
    curl -s http://169.254.169.254/latest/meta-data/$1
}

function get_hwaddr {
    ifconfig $1 | awk '/^[a-z]/{print $NF}'
}

TARGET=eth1
NET_NAME=ec2
HWADDR=$(get_hwaddr $TARGET)
ENI_ID=$(get_metadata network/interfaces/macs/$HWADDR/interface-id)
MY_ID=$(get_metadata instance-id)

echo ENI=$ENI_ID
echo INSTANCE=$MY_ID

docker network rm $NET_NAME
docker network create -d ipvlan --ipam-driver ec2-eni -o parent=eth1 --ipam-opt instance-id=$MY_ID --ipam-opt eni-id=$ENI_ID $NET_NAME
