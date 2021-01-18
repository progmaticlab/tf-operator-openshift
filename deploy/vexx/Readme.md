# Install ovenshift on vexx infra

Node for run installation scripts below:
- CentOS 7
- 2G RAM
- 10G Disk Space

Deploy will automatically create bootstrap node, 3 master nodes and 3 worker nodes in vexx cloud.

1.   Setup you clouds.yaml file as instucted here: https://docs.openstack.org/python-openstackclient/pike/configuration/index.html . Set your openstack cloud using OS_CLOUD env variable
```
#Example:
cat ~/.config/openstack/clouds.yaml 
clouds:
  vexx:
    auth:
      auth_url: https://auth.vexxhost.net
      project_name: <project name>
      username: <user>
      password: <password>
      project_domain_name: default
      user_domain_name: Default
    region_name: sjc1
```

2. Crete two IP addresses inside your OpenStack cloud

```bash
openstack floating ip create --description "API <cluster_name>.<base_domain>" <external network>
openstack floating ip create --description "Ingress <cluster_name>.<base_domain>" <external network>
```

3. Add DNS Records to your base domain

```
api.<cluster_name>.<base_domain>.  IN  A  <API_FIP>
*.apps.<cluster_name>.<base_domain>. IN  A <apps_FIP>
```

4. Set up required env variables:

- OPENSHIFT_PUB_KEY - Public keys to be uploaded on openshift machines for user 'core'
- OPENSHIFT_PULL_SECRET - Pull secret for download openshift images https://cloud.redhat.com/openshift/install/pull-secret.
- OPENSHIFT_CLUSTER_NAME - Cluster name for your openshift cluster. The name will be used as a part of API and Ingress domain names
- OPENSHIFT_BASE_DOMAIN - base domain name for your cluster
- OPENSHIFT_API_FIP - Floating IP address for your openshift API
- OPENSHIFT_INGRESS_FIP - Floating IP address for your openshift Ingress

5. Run install script:

```bash
./install_openshift.sh
```
