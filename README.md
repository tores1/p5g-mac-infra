# p5g-mac-infra
Stands up a simple k8s cluster suitable for installing the p5g-helm chart using kubeadm on a Mac using Multipass and Vbox.
## K8s cluster
The cluster will consist of a single master and multiple workers. Calico will be installed for networking.
The SCTP alpha feature gate will be enabled. Each node will have two iterfaces. enp0s3 will be used by multipass and eps0s8 will be used by k8s.
## Requirements
Requires [multipass](https://multipass.run/docs/installing-on-macos) for mac as well as virtualbox and helm for installing the charts.\
Install homebrew: go to [brew.sh](https://brew.sh/)\
Install multipass: `$ brew cask install multipass`\
Install virtualbox: `$ brew cask install virtualbox` Note: see cask [documentation](https://formulae.brew.sh/cask/virtualbox). \
Install kubectl: `$ brew install kubectl`\
Install helm: `$ brew install helm`
### Networking
In order to emulate an on-premise environment and have the ability to connect a real eNB to the p5g-helm EPC, this script will
require that the 'host' networking feature of vbox will be used which means that every VM/k8s node will be reachable from the mac host's network.
In order to maintain stable IP adresses for eg. an external
eNB, this script requires fixed IP adresses for the cluster nodes as well as the Metallb load balancer. The addresses are
assigned by editing the create-vbox.sh script (see instructions in the script).
A minimum of 4 ip adresses will be needed; one for the load balancer and 3 for the nodes. As such, you may have to adjust the settings of
the network to ensure that these 4 adresses are not assigned to other workloads using eg. DHCP.
## Use
`$ cd p5g-mac-infra`\
Edit `create-vbox.sh` to match your networking environment (see instructions in `create-vbox.sh`).\
Run the installer: `$ bash create-vbox.sh`\
The cluster nodes will be created and the workers will be attached to the single master.\
To set kubectl to use your new cluster: \
`$ export KUBECONFIG=$(pwd)/kube-config`
## Installing the EPC using Helm
`$ git clone https://github.com/tores1/p5g-helm.git`\
`$ cd p5g-helm\charts\p5g`\
See readme of p5g-helm for further instructions on how to modify the `p5g-helm\charts\p5g\values.yaml` file to match your network. \
`$ helm install my-epc .` \
Use kubectl to inspect the running cluster.
