#!/bin/bash
# creates a k8s cluster using virtualbox, metallb and calico. Only single master is supported.
# dependencies: virtualbox installed, multipass using 18.04 images, macOS 
# File dependencies: calico.yaml, c-init.yml, kubelet-update.sh, kubeadm-init.tmpl, metallb-config.yaml, node-netplan.tmpl
# This file and file dependencies need to be in the same directory. CD to this directory and start with sudo bash create-vbox.sh

# This setup will use the mac's host network and IP adress space - static IP's will be used.
# Metallb will use IP adresses from this same space as per the Metallb configuation.
# multipass for mac and vbox will occupy enp0s3 on IP 10.0.2.15 for all guest hosts.
# K8s will use port enp0s8 which is mapped to the $mac_port_id.
# SCTP is enabled on the kube-apiserver.

# Update the name of master1 node and worker nodes (below).
# Nodes are defined using the format of <node/host name>;<ip address>
# The $gateway sets the default route and $dns the name server. Mupltipe DNS servers are possible to define (separte by commas).
# $net is the netmask (/xx) of the host/k8s network
# $mac_port_id is the port id of the mac that the guest's enp0s8 port will share.
# $pod_subnet_cidr is used by kubeadm as-is. The standard kubeadm service subnet is not changed from default (10.96.0,0/12)

set -e
# set -x
# define nodes
master1_ip='master;192.168.1.145'
export workers_ip='worker1;192.168.1.146 worker2;192.168.1.147'
export dns='192.168.1.1'
export gateway='192.168.1.1'
export net='24'
export pod_subnet_cidr='10.1.0.0/16'
mac_port_id='en1'

##################

export nodes_ip="$master1_ip $workers_ip"

master1=$(echo $master1_ip | awk -F ";" '{print $1}')
workers=$(
for node in $workers_ip
do
	echo $node | awk -F ";" '{print $1}'
done)
nodes="$master1 $workers"

# Create images and connect brideged network
for node in $nodes_ip
do 
  export name=$(echo $node | awk -F ";" '{print $1}')
  multipass launch -n $name -c 2 -d 10G -m 2G --cloud-init c-init.yml
  multipass stop $name
  sleep 5
  sudo vboxmanage modifyvm $name --nic2 bridged --bridgeadapter2 $mac_port_id
  multipass start $name
  #TODO: use AWK to extract enp0s8
  export ip=$(echo $node | awk -F ";" '{print $2}')
  netplan=$(cat node-netplan.tmpl | envsubst) 
  multipass exec $name -- sudo /bin/bash -c  "cat > /etc/netplan/60-bridge.yaml" <<- EOF
	${netplan}
	EOF
  multipass exec $name sudo netplan apply
done


# start kubernetes on master
export ip_of_master=$(multipass exec $master1 -- ip addr show enp0s8 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
init_file=$(cat kubeadm-init.tmpl | envsubst) 
multipass exec $master1 -- bash -c  'cat > $HOME/init-config.yaml' <<- EOF
	${init_file}
	EOF
multipass exec $master1 -- sudo bash -c 'kubeadm init --config $HOME/init-config.yaml'

# install kubeconfig file and set KUBECONFIG and transfer kube config file to local pwd directory.
multipass exec $master1 -- bash -c ' 
  mkdir -p $HOME/.kube  
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config
  echo -e "\nexport KUBECONFIG=$HOME/.kube/config" >> ~/.bashrc
  source ~/.bashrc
'
master_home=$(multipass exec $master1 -- /bin/bash -c 'echo $HOME')
multipass transfer $master1:$master_home/.kube/config kube-config
echo Kube config file written to $(pwd)/kube-config
echo Execute the following to access via kubectl: export KUBECONFIG=$(pwd)/kube-config

# join worker nodes to cluster
join_command=$(multipass exec $master1 -- sudo kubeadm token create --print-join-command)
for worker in $workers
do
	multipass exec $worker -- sudo $join_command
done

# set node ip in kubelet config file and restart kubelets
for node in $nodes
do
	multipass transfer kubelet-update.sh $node:
	multipass exec $node -- sudo bash kubelet-update.sh
done

#install calicoctl on master1  
multipass exec $master1 -- sudo curl -L -o /usr/local/bin/calicoctl https://github.com/projectcalico/calicoctl/releases/download/v3.14.1/calicoctl
multipass exec $master1 -- sudo chmod +x /usr/local/bin/calicoctl
multipass exec $master1 -- /bin/bash -c '
  echo -e "\nexport DATASTORE_TYPE=kubernetes" >> ~/.bashrc
  source ~/.bashrc
' 
# set calicoctl config and datastore type on this host
echo Execute the following to use calicoctl on this host: export DATASTORE_TYPE=kubernetes

cat > $(pwd)/calicoctl.conf <<- EOF 
	apiVersion: projectcalico.org/v3
	kind: CalicoAPIConfig
	metadata:
	spec:
	  datastoreType: "kubernetes"
	  kubeconfig: "$(pwd)/kube-config"
EOF

#create local directory for db storage to be used by k8s PersistentVolume
for worker in $workers
do
	multipass exec $worker -- sudo mkdir /mongodb-storage
done

# install calico
kubectl apply -f calico.yaml --kubeconfig=kube-config

# Install metallb
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.3/manifests/namespace.yaml --kubeconfig=kube-config
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.3/manifests/metallb.yaml --kubeconfig=kube-config
# On first install only
kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)" --kubeconfig=kube-config
# Create L2 LB at IP range
kubectl apply -f metallb-config.yaml --kubeconfig=kube-config
