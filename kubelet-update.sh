#!/bin/bash

cp /var/lib/kubelet/kubeadm-flags.env $HOME/kubeadm-flags.env.bak
ip=$(ip addr show enp0s8 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
file=$(sed '$ s/.$//' /var/lib/kubelet/kubeadm-flags.env)
newfile=$(echo $file --node-ip=${ip} \")
echo $newfile > /var/lib/kubelet/kubeadm-flags.env
systemctl daemon-reload && systemctl restart kubelet
