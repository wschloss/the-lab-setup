#!/bin/bash

set -e
source ./config

# Verifies if doctl is available
verify_doctl() {
  if ! [ -x $(command -v doctl) ]; then
    echo 'This setup requires doctl'
    exit 1
  fi
}

# Provisions one droplet
# usage: provision_droplet $droplet_name
provision_droplet() {
  command="doctl compute droplet create $1 \
    --size $INSTANCE_SIZE \
    --image $IMAGE \
    --region $REGION \
    --ssh-keys $SSH_PUB_KEY_FINGERPRINT \
    --wait"

  echo $command
  eval $command > /dev/null
}

# Provisions the master and all worker droplets
provision_all_droplets() {
  echo 'Provisioning droplets. This step is currently synchronous and may take a while.'
  echo $SEPARATOR
  echo 'Creating master node'
  echo $SEPARATOR
  provision_droplet $MASTER
  echo $SEPARATOR

  for i in $WORKERS; do
    echo "Creating worker: $i"
    echo $SEPARATOR
    provision_droplet $i
    echo $SEPARATOR
  done
}

# Returns the ID of the droplet with the given name
# usage: get_droplet_id_by_name $droplet_name
get_droplet_id_by_name() {
  doctl compute droplet list --format "Name,ID" | grep $1 | awk '{ print $2 }'
}

# Returns the public ipv4 of the droplet with the given name
# usage: get_droplet_ip_by_name $droplet_name
get_droplet_ip_by_name() {
  doctl compute droplet list --format "Name,PublicIPv4" | grep $1 | awk '{ print $2 }'
}

# Collects $WORKER_IDS var into one string, comma separated, and prepended by
# the given arg
# usage: collect_worker_ids_by_comma $prepend_to_id
collect_worker_ids_by_comma() {
  ret_val=""
  for i in $WORKER_IDS; do
    ret_val="$ret_val$1$i,"
  done
  echo "${ret_val%?}"
}

# Provisions all the necessary firewalls
# Requires $MASTER_ID and $WORKER_IDS to be defined
provision_and_apply_firewalls() {
  allow_all_outbound_and_all_internal_and_inbound_ssh="doctl compute firewall create \
    --name allow-all-outbound-and-all-internal-and-inbound-ssh \
    --droplet-ids $MASTER_ID,$(collect_worker_ids_by_comma '')
    --inbound-rules 'protocol:icmp,droplet_id:$MASTER_ID,$(collect_worker_ids_by_comma 'droplet_id:') \
      protocol:tcp,ports:all,droplet_id:$MASTER_ID,$(collect_worker_ids_by_comma 'droplet_id:') \
      protocol:udp,ports:all,droplet_id:$MASTER_ID,$(collect_worker_ids_by_comma 'droplet_id:')
      protocol:tcp,ports:22,address:0.0.0.0/0,address:::/0' \
    --outbound-rules 'protocol:icmp,address:0.0.0.0/0,address:::/0 \
      protocol:tcp,ports:all,address:0.0.0.0/0,address:::/0 \
      protocol:udp,ports:all,address:0.0.0.0/0,address:::/0'"
  allow_all_tcp_80_inbound="doctl compute firewall create \
    --name allow-all-tcp-80-inbound \
    --droplet-ids $(collect_worker_ids_by_comma '') \
    --inbound-rules 'protocol:tcp,ports:80,address:0.0.0.0/0,address:::/0'"
  allow_all_tcp_6443_inbound="doctl compute firewall create \
    --name allow-all-tcp-6443-inbound \
    --droplet-ids $MASTER_ID \
    --inbound-rules 'protocol:tcp,ports:6443,address:0.0.0.0/0,address:::/0'"

  echo 'Applying firewall rules'
  echo $SEPARATOR

  echo $allow_all_outbound_and_all_internal_and_inbound_ssh
  eval $allow_all_outbound_and_all_internal_and_inbound_ssh > /dev/null
  echo $SEPARATOR

  echo $allow_all_tcp_80_inbound
  eval $allow_all_tcp_80_inbound > /dev/null
  echo $SEPARATOR

  echo $allow_all_tcp_6443_inbound
  eval $allow_all_tcp_6443_inbound > /dev/null
  echo $SEPARATOR
}

# Configures user, adds sudo permissions, adds ssh key to that user, updates packages, and installs docker
# usage: configure_node $ip_addr
configure_node() {
  echo "Configuring $1"
  command="adduser --disabled-password --gecos '' $USER \
    && echo '$USER ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/100-$USER \
    && mkdir -p /home/$USER/.ssh \
    && cp /root/.ssh/authorized_keys /home/$USER/.ssh/ \
    && chown $USER:$USER /home/$USER/.ssh/authorized_keys \
    && apt-get -y update && apt-get -y upgrade \
    && apt-get install -y docker.io \
    && usermod -aG docker $USER"

  echo "ssh -i $SSH_PRIV_KEY root@$1 \"$command\""
  ssh -i $SSH_PRIV_KEY root@$1 "$command"
}

# Configures the master and worker nodes. Requires $MASTER_IP and $WORKER_IPS to be set
configure_all_nodes() {
  echo 'Configuring nodes. This step is currently synchronous and may take a while'
  echo $SEPARATOR
  configure_node $MASTER_IP
  echo $SEPARATOR
  for i in $WORKER_IPS; do
    configure_node $i
    echo $SEPARATOR
  done
}

# Installs k8s pacakges on the given ip addr
# usage: install_kubernetes_packages $ip_addr
install_kubernetes_packages() {
  echo "Installing k8s packages on $1"
  echo $SEPARATOR
  command="apt-get install -y apt-transport-https curl \
    && curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - \
    && echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' > /etc/apt/sources.list.d/kubernetes.list \
    && apt-get update \
    && apt-get install -y kubelet kubeadm kubectl \
    && apt-mark hold kubelet kubeadm kubectl"
  echo "ssh -i $SSH_PRIV_KEY root@$1 \"$command\""
  ssh -i $SSH_PRIV_KEY root@$1 "$command"
}

# Installs all necessary packages for kubeadm install. Configures one master and
# joins worker nodes to the cluster. Requires $MASTER_IP and $WORKER_IPS to be set
install_and_configure_kubernetes() {
  echo 'Installing k8s pacakges on all nodes. This step is currently synchronous and may take a while'
  echo $SEPARATOR
  install_kubernetes_packages $MASTER_IP
  echo $SEPARATOR
  for i in $WORKER_IPS; do
    install_kubernetes_packages $i
    echo $SEPARATOR
  done

  echo 'Initializing kubernetes master'
  echo $SEPARATOR
  command="kubeadm init --pod-network-cidr=192.168.0.0/16"
  echo "ssh -i $SSH_PRIV_KEY root@$MASTER_IP \"$command\""
  ssh -i $SSH_PRIV_KEY root@$MASTER_IP "$command" 
  echo $SEPARATOR

  # Get the kubeadm token
  kubeadm_token=$(ssh -i $SSH_PRIV_KEY root@$MASTER_IP kubeadm token list | sed -n 2p | awk '{ print $1 }')
  echo 'Joining workers to the cluster'
  echo $SEPARATOR
  command="kubeadm join --token $kubeadm_token $MASTER_IP:6443 --discovery-token-unsafe-skip-ca-verification"
  for i in $WORKER_IPS; do
    echo "ssh -i $SSH_PRIV_KEY root@$i \"$command\""
    ssh -i $SSH_PRIV_KEY root@$i "$command"
    echo $SEPARATOR
  done
}

# Copies admin config to local machine ~/.kube/config
# Requires $MASTER_IP to be set
setup_local_kubeconfig() {
  echo 'mkdir -p ~/.kube'
  mkdir -p ~/.kube
  echo "scp -i $SSH_PRIV_KEY root@$MASTER_IP:/etc/kubernetes/admin.conf ~/.kube/config"
  scp -i $SSH_PRIV_KEY root@$MASTER_IP:/etc/kubernetes/admin.conf ~/.kube/config
}

# ----------------------------------------------------------

verify_doctl
provision_all_droplets

MASTER_ID=$(get_droplet_id_by_name $MASTER)
WORKER_IDS=""
for i in $WORKERS; do
  WORKER_IDS="$WORKER_IDS $(get_droplet_id_by_name $i)"
done

MASTER_IP=$(get_droplet_ip_by_name $MASTER)
WORKER_IPS=""
for i in $WORKERS; do
  WORKER_IPS="$WORKER_IPS $(get_droplet_ip_by_name $i)"
done

provision_and_apply_firewalls
configure_all_nodes
install_and_configure_kubernetes
read -p 'Would you like to setup your local kubeconfig (NOTE: this will overwrite ~/.kube/config)? [y/N]: ' setup_kubeconfig
if [[ "$setup_kubeconfig" =~ ^(yes|y)$ ]]; then
  setup_local_kubeconfig
fi

echo
echo "Your kubernetes cluster is ready for use at $MASTER_IP:6443"
echo "If you did not setup your local kubeconfig, you will need to manually retrieve / create a kubeconfig file"
echo "Once you have kubectl installed and a kubeconfig ready, you can proceed to run ./platform_setup/setup.sh"
echo