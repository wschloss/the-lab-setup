# 'The Lab' platform setup
This project sets up and configures the Digital Ocean infrastructure to support a kubernetes based platform for testing out hobby projects

## PREREQUISITES
- Install and configure [doctl](https://github.com/digitalocean/doctl). You should include your API access token in your doctl configuration, which is typically at ~/.config/doctl/config.yaml:
```yaml
access-token: YOUR_TOKEN_HERE
```
- Add an ssh key to your Digital Ocean account

## SETUP INFRASTRUCTURE
*NOTE: This is NOT a production app style setup, but rather automatically creates and configure a cluster for testing hobby projects*
- Update the ./infrastructure_setup/config file with appropriate settings
- The following script will setup one master node and worker nodes in your Digital Ocean account based on your ./infrastructure_setup/config file settings. It will then configure each node and install kubernetes with kubeadm
```
chmod +x ./infrastructure_setup/setup.sh
./infrastructure_setup/setup.sh
```
- After the script has completed setting up kubernetes, it will proceed to install a pod overlay network (weavenet), tooling / dev / prod namespaces, a docker registry and gogs for version control, and a simple 'under construction' server for the dev and prod namespaces
- Note that gogs and docker registry are intentionally scheduled on the master node. The master node is not meant for servicing app requests, but is used in this setup for storage of images and source. If your hobby project contains large images, another volume should be mounted for gogs / registry, or version control and image storage should be done elsewhere.
- The dev namespace is meant for 'in development' app versions, while the prod namespace is meant for a stable release to expose.

The following ports / firewalls are setup:

* 22 -> all nodes allow ssh with the key pair specified in config
* 6443 -> the master node will expose 6443 to any IP for kubernetes api server access. Access still requires a valid kubeconfig
* 30500 -> worker nodes will send port 30500 traffic to dev under-construction-server. Only $MY_IP from config can access this port
* 30501 -> worker nodes will send port 30501 traffic to prod under-construction-server. All IPs can access this port
* 31000 -> worker nodes will send port 31000 traffic to gogs. Only $MY_IP from config can access this port

## CLEANUP
- Delete all droplets and firewalls in your Digital Ocean account
