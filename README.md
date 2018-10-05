# 'The Lab' platform setup
This project sets up and configures the Digital Ocean infrastructure to support a CI / CD platform on kubernetes

## PREREQUISITES
- Install and configure [doctl](https://github.com/digitalocean/doctl). You should include your API access token in your doctl configuration, which is typically at ~/.config/doctl/config.yaml:
```yaml
access-token: YOUR_TOKEN_HERE
```
- Add an ssh key to your Digital Ocean account

## SETUP INFRASTRUCTURE
- Update the ./infrastructure_setup/config file with appropriate settings
- The following script will setup one master node and worker nodes in your Digital Ocean account based on your ./infrastructure_setup/config file settings. It will then configure each node and install kubernetes with kubeadm
```shell
chmod +x ./infrastructure_setup/setup.sh
./infrastructure_setup/setup.sh
```

## CLEANUP
- Delete all droplets and firewalls in your Digital Ocean account
