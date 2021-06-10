# EKS Implementation Version 3

This demo utilize EKSCTL to create and operate a cluster.

EKSCTL is a CLI tool developed by Weaveworks (then promoted to be the official AWS EKS CLI) to create/operate an EKS cluster quickly. It used Cloudformation under-the-hood.

https://eksctl.io/

## What Gets Deployed
By default, if you run the command without any customizations, EKSCTL will provision:
- A dedicated VPC and subnets across 2 AZ's
- A cluster with 2 m5.large worker nodes (using the EKS AMI)

You can use a YAML file to override the defaults and specify this file when running the command to create the cluster.


## Instructions

#### Install EKSCTL
- https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html

Run `eksctl version` to ensure it's available locally.


#### Run the Command
`eksctl create cluster -f eks-cluster.yml`

This will utilize a local YAML file to override defaults (specifically to create smaller worker nodes for cost-saving purposes).

The YAML files uses a pre-existing EC2 keypair.

This will take about 10-15 minutes to run, at which point your local kubeconfig file will be updated and your cluster will be ready for use.

Verification:
`kubectl config view --minify`
`kubectl get nodes`


#### Manage the Node Groups

The following commands can get you some basic info on your cluster & nodegroup:
`eksctl get cluster`
`eksctl get nodegroup --cluster kag-eksctl-cluster`


**To Scale a NodeGroup:**\
`eksctl scale nodegroup -n kag-eksctl-ng-1 -N 5 -M 5 --cluster kag-eksctl-cluster`
- This will scale the nodes via the CF template that manages the NodeGroup.

**To add a new NodeGroup:**\
Add the following block of code to the YAML file (under the *NodeGroup* section) and then run the below command to add it:
```
- name: kag-eksctl-ng-mixed
  minSize: 3
  maxSize: 5
  instancesDistribution:
    maxPrice: 0.2
    instanceTypes: ["t2.small", "t3.small"]
    onDemandBaseCapacity: 0
    onDemandPercentageAboveBaseCapacity: 50
  ssh:
    publicKeyName: kabirg
```

This block will allow you to provision a NodeGroup that uses 50% on-demand instances, and 50% spot instances.

Command:\
`eksctl create nodegroup --config-file eks-cluster.yml`

Reference: https://eksctl.io/usage/spot-instances/

**To Drain/Delete a NodeGroup:**\
NodeGroups are immutable. So if you need to update it (like to change the AMI or instance type), you'll have to replace it. This is where draining will come in handy to protect your workloads.

`eksctl delete nodegroup -f eks-cluster.yml --include kag-eksctl-ng-mixed --approve`
- This command will drain (re: remove all pods) and cordon (re: mark as unschedulable) the nodes before deleting them.
- `--approve` means that the command will NOT run in dry-run mode.
- `--include` can be used to delete just a single NG from the config file.


#### Deploy a Cluster AutoScaler
The CAS is a K8S deployment that you run in your cluster (not limited to EKS) which handles autoscaling based on resource utilization.

Source: https://github.com/kubernetes/autoscaler

- NG’s that are multi-AZ (implemented in stateless environments where the app isn’t tied to AZ-specific EBS volumes) use multi-AZ scaling.
- NG’s that are single-AZ (implemented in stateful environments where the app is tied to AZ-specific EBS volumes) use single-AZ scaling.

Commented out in the YAML file are 3 new node groups which use labels to distinguish our stateful/stateless workloads and our spot/on-demand instances. They all also use the `iam / withAddonPolicies / autoScaler` property to indicate that those nodes will be viewed as part of the CAS.

Notes:
- Notices that the spot-based NG uses multiple instance-types (to increase chances of instances being available).
- It also sets the `onDemandBaseCapacity / onDemandPercentageAboveBaseCapacity` properties to `0` so that it fully uses spot instances.
- Deploy those 3 NG's prior to deploying the CAS.

**Deploy the CAS:**\
`kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml`

Annotate the CAS so that it doesn't doesn't remove it's own pods by accident:
`kubectl -n kube-system annotate deployment.apps/cluster-autoscaler "cluster-autoscaler.kubernetes.io/safe-to-evict"="false"`
Source: https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md

Edit the deployment config so that you plug in your EKS cluster name into the `container` property's placeholder, and to use a CAS image ID that matches the version of your cluster.
`kubectl edit deployment cluster-autoscaler -n kube-system`
Source: https://github.com/kubernetes/autoscaler/releases?after=cluster-autoscaler-chart-9.1.0

**Test out the Autoscaler:**\
Try deploying the NGINX deployment in this folder.
- It will only be deployed onto the spot instances and requires a certain amount of resources that, when you scale the deployment beyond 2 pods, will force the autoscaler to increase the number of nodes to handle it.
- A Pod will be in a `pending` state until the new node is provisioned to handle it.
- YOu can also view the event log to see what triggered the scaling:
`kubectl -n kube-system logs deployment/cluster-autoscaler | grep -iA5 'expanding node group'`


#### Control-Plane Logging
The control-plane is completely managed by AWS, but at an extra cost, you can choose to enable logs for any of the control-plane components.

They will each have their own stream under the `/aws/eks/[CLUSTER_NAME]/` log group.
- [ api | audit | authenticator | controllerManager | scheduler ]

Utilize this block of code to enable it:
```
cloudWatch:
  clusterLogging:
    enableTypes: ["*"]
```

To apply this (assuming the cluster is already created), run `eks util update-cluster-logging -f xxx.yml --approve`


#### Container Insight Metrics
To get insights into the utilization metrics of our containers, we use the CloudWatch agent. In a nutshell:
- Add the `CloudWatchAgentServerPolicy` IAM policy to the NodeGroup roles allowing them the requisite CloudWatch access for the agent to work.
- We deploy the CloudWatch agent as a DaemonSet in our cluster.
- We also deploy Fluend as a DaemonSet. Fluentd is a service that can collect, process and output logs. It's useful in K8s because it grabs the container logs and forwards them to CloudWatch.

To deploy:\
`curl https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/master/k8s-yaml-templates/quickstart/cwagent-fluentd-quickstart.yaml | sed "s/{{cluster_name}}/kag-eksctl-cluster/;s/{{region_name}}/us-east-1/" | kubectl apply -f -`

Verify:
`kubectl get ds --all-namespaces | grep cloudwatch`
You should see the CW Agent and Fluentd Daemonset.

If you'd done both steps (IAM and Daemonset deployment), you should be able to navigate to `Cloudwatch > Metrics > Container Insights` in the AWS Console.

Source:
- https://medium.com/attest-r-and-d/kubernetes-logs-to-aws-cloudwatch-with-fluentd-ede8d88a1b4e
- https://medium.com/swlh/fluentd-simplified-eb5f19416e37


#### Helm
Helm is a package manager for Kubernetes.
- "Releases" are running instances of "Charts". Charts are the "packages" containing all the code/dependencies for the app you want to install.
- You use the Helm CLI client to search repos, install/uninstall charts, etc...

Installation
`brew install helm`\
`helm version`

**Getting Started:**
- `Add` a Helm repo which contains charts that we can install:\
`helm repo add stable https://charts.helm.sh/stable/`\
`helm repo list` - shows all installed repo's.\
`helm repo update` - pulls any latest charts down into your local repo.\
- Install a Chart:\
`helm install [CUSTOM_NAME] stable/xxx`
- List all installed charts: `helm ls`


#### Authentication & Authorization

**Create an Admin User:**\
Create an admin IAM user, map it to an RBAC role, and test.
- Create the user in IAM
- Add an entry to the `mapUsers` secion of the AWS-Auth file to map the IAM-entity to the pre-defined `system:masters` K8s ClusterRole.
`kubectl get cm aws-auth -n kube-system -o yaml > awsauth.yml`
```
 - userarn: arn:aws:iam::637661158709:user/test-eks-admin
    username: test-eks-admin
    groups: system:masters
```
`kubectl apply -f awsauth.yml -n kube-system`
- Finally, configure the IAM credentials locally so you can use that user when running your kubectl commands. You can't use a `--profile` option for kubectl commands so export the `AWS_PROFILE` envvar to switch accounts. Then you can run your commands

Create a read-only user that only has access to a particular namespace.
- This is the same process as above except we have to create a namespace, role, and rolebinding in addition to the IAM-entity, and aws-auth entry.
- The K8s role & rolebinding will both specify a particular namespace. The role grants authorizations. The rolebinding will bind that role to an IAM user. That IAM user isn't found by K8s until you map it through AWS-Auth.


#### Metrics Server and Dashboard
Metrics Server is an open-source monitoring tool that can retrieve pod-level metrics from the kubelet API (Kubelet contains cAdvisor which exposes these metrics through the API).

**Deploy Metrics Server:**
- Install and unzip the Metrics Server package:\
  `wget -O v0.3.6.tar.gz https://codeload.github.com/kubernetes-sigs/metrics-server/tar.gz/v0.3.6 && tar -xzf v0.3.6.tar.gz`
- Deploy it to the cluster:\
  `kubectl apply -f metrics-server-0.3.6/deploy/1.8+/`
- Verify it was deployed:\
  `kubectl get deployment metrics-server -n kube-system`\
  `kubectl top pod`


**Deploy the Kubernetes Dashboard:**\
Run the following:\
`kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-beta8/aio/deploy/recommended.yaml`


**Access the Dashboard:**\
In order to access API with an HTTP client like a web browser, we can run kubectl in a mode where it acts like a reverse proxy between our local workstation and the API server. Kubectl will take care of location and authenticating to the server.

The Dashboard will require a token for us to authenticate. Let's create an admin Service Account, and use it's token for our authentication.

Run the following to create the Service Account:\
`kubectl appy -f sa.yml`

- Retrieve the cluster authentication token with this command:\
  `kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep cluster-admin-sa | awk '{print $1}')`
- Start the proxy: `kubectl proxy`
- Access this URL from a browser:\
`http://127.0.0.1:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy`
- Enter the token when prompted.


### Deploy a Stateless Guestbook App
Src: https://github.com/kubernetes/examples/tree/master/guestbook

Going to test deploying a sample stateless application provided by K8S documentation. We'll deploy:
- Te backend resources: a Redis master and slave pods, as well as services for both (so that they are exposed with a fixed URL).
- The frontend resources: a PHP app).

It's a stateless app so we can practice scaling the pods easily. We'll also do some chaos testing by deleting pods and test the resiliency.

**Backend Deployment:**\
We'll deploy the Redis master and slave pods/services first.

Run the following to deploy the Redis Master:\
`kubectl apply -f apps/sample-stateless-app/redis-master.yaml`

Run the following to deploy the 2 Redis Slaves:\
`kubectl apply -f apps/sample-stateless-app/redis-slaves.yaml`

Notes:
- `kubectl get po,svc` will show you the pods and services we just deployed. You'll see that the Redis resources are exposed internally within the cluster through the ClusterIP service.
- In the redis-slave.yml, we deploy 2 replicas to get 2 slave-pods. It also uses **GET_HOSTS_FROM=dns** environment variable that allows the slave to retrieve the Master pod's hostname from Kubernetes' internal DNS service.
- In K8s, there are many 3rd party CNI implementations (Flannel, Calico, Weave, etc..). Amazon has the **VPC CNI Plugin** based around ENI's. This plugin is installed into you EKS nodes via the **aws-node** Daemonset.
  - Do a `kubectl get po -o wide` to see the private IP's of the pods and which nodes they're running on.
  - Do a `kubectl describe node xxx`, with *xxx* being the Node value provided by the previous command. In this output, you'll get the Instance-ID which you can then reference in the AWS console.
  - In the AWS console, find that instance, You'll see a bunch of Secondary Private IP's. Each of these are IP's of the pods running on that node. You'll see the IP's of the Redis pods in addition to some IP's of additional pods running on the node (the `describe node` command will show all pods running on that node including kube-proxy, aws-node, etc...).
  - These IP's correspond to the ENI's attached to the instance. There is a limit to how many ENI's you can attach to a node, and how many IP's per ENI you can have.

**Frontend Deployment:**\
We'll deploy the Guestbook pod and loadbalancer service to publicly expose the application via an ELB

Run the following to deploy the Guestbook app:\
`kubectl apply -f apps/sample-stateless-app/frontend.yaml`

Notes:
- The YAML file uses service-type **LoadBalancer** to create an ELB that listens on port 80. Under-the-hood (you can verify by desribing the service) is sends the traffic to a high port on the machine via the NodePort service. From there it sends the traffic to the Pod which is listening on port 80.
- Do a `kubectl get service frontend` to see the port-mapping. If you look at the ELB in the AWS console, you'll see the port-forwarding rule which corresponds to this mapping.

You can now access the app from a browser!

You can use the `kubectl scale` command (or modify the YAML directly, even better) to scale the pods easily. If you install/start the dashboard, you can edit the YAML or scale the Deployment directly from the UI as well.

Try deleting pods or shutting down nodes and watch K8S recreate pods or shift them to other nodes to react to the chaos.


### Deploy a Stateful Wordpress App w/EBS
Going to test deploying a stateful Wordpress application using EBS. We'll deploy:
- A Storage Class and Persistent Volume
- The MySQL backend, along with service to expose it and a PV (EBS) to back the data.
- The Wordpress app (as both a Deployment and StatefulSet), along with a PV (EBS) to hold the static content and a LoadBalancer service to expose the app publicly.

Note: using EBS is not a great way to do this because it is tied to a single AZ (so if a pod dies, it must be recreated within the same AZ to access the volume). The best way to deploy Wordpress is a shared volume avaialable across AZ's (EFS), which we'll do next.

**Create the Namespace, SC and PVC's for Wordpress & MySQL:**
- `kubectl create ns wordpress1`
- With K8s v1.11, a default GP2 SC is provided in our cluster. It uses the *aws-ebs* provisioner so that any claims against it will create EBS volumes.
- `kubectl apply -f apps/stateful-app/pvcs.yaml -n wordpress1`
- Now we should have 2 EBS volumes (one from each PVC)

**Deploy the MySQL Backend**
- `kubectl create secret generic mysql-pass --from-literal=password=test-pw --namespace=wordpress1`
- `kubectl apply -f apps/stateful-app/deploy-mysql.yaml --namespace=wordpress1`

Notes:
- THe MySQL container we deploy uses an evvar which grabs the password from the secret we created.
- The template we deploy also uses one of the PVC's we created, and mounts it to a directory within the container. This allows for data written within the container to persist on the EBS volume.
- Once created, if you list the PVC's, you'll see that the MySQL PVC is now bound (in the EBS console, you'll see the status of the volume go from 'available' to 'in-use').

**Deploy the Wordpress App**
- `kubectl apply -f apps/stateful-app/deploy-wordpress.yaml --namespace=wordpress1`

Notes:
- Deployments are used for stateless applications.
- If you have a stateful app, you can use a Deployment with a PVC (like an EBS volume), but there is a problem:
  - EBS volumes attach to nodes, so all pods have to be on that single node to access the volume.
  - This also means that all pods will access the *same* volume (i.e the same EBS volume on that node is mounted into all pods). This is problematic b/c all pods can now step on eachother's toes.
- We can solve the first problem (forcing all pods to a single node) by switching to shared storage like EFS. But this doesn't fix the problem of many pods using one storage. StatefulSets can solve this problem.
- StatefulSets spin up pods sequentially (suffixed w/sequential numbers). Each pod also *gets its own PVC* regardless of which node that pod is created/re-created on.
  - This makes it very useful for deploying Stateful apps (hence the name).
  - Additionally, StatefulSets are useful when you need to create pods in a particular order (i.e a MySQL master *before* its slaves).
Src: https://medium.com/stakater/k8s-deployments-vs-statefulsets-vs-daemonsets-60582f0c62d4

So to truly deploy our Stateful application properly, we should use a Stateful set with an EFS backend. This allows our pods to not be limited to a single node, and it allows them to use shared storage (so if we upload data from one pod, it's not in it's isolated volume and inaccessible from the other pod).
- Do they step on eachother toes with respect to writing to the same mounted storage?
- We'll do this next.


### Deploy a Stateful Wordpress App w/EFS
Going to test deploying a stateful Wordpress application using EFS. We'll deploy:
- EFS is a managed network filesystem that can be attached to any EC2 instance in a multi-AZ setup.
- We have to enable EFS, create the namespace, provisioner, storageclass & PVC's, admin RBAC permissions (to access the filesystem), then deploy the backend/frontend.

Steps:
- Enable and create the filesystem in the console. Make sure to attach it to the worker-node security group to prevent any issues with attaching the system to the EC2 nodes.
- Install `amazon-efs-utils` in all your worker-nodes.
- Create the namespace.
- Deploy the template which creates a Deployment for the efs-provisioner, you need to update this template with the ID of your existing filesystem. This is referenced by our storageclass template.
- Deploy the template which creates the SC and PVC's (for MySQL and Wordpress). These 2 PVC's will create 2 directories on our filesystem.
- Deploying the backend/frontend is the same process as before.


#### EKS Monitoring with Prometheus & Grafana
**Prometheus** collects cluster metrics and stores them in a timeseries database.
**Grafana** provides a dashboard for us to present our metrics for analysis.

**Install Prometheus:**
- Create a seperate namespace:\
`kubectl create namespace prometheus`
- Install it via Helm chart:
```
helm install prometheus stable/prometheus \
    --namespace prometheus \
    --set alertmanager.persistentVolume.storageClass="gp2" \
    --set server.persistentVolume.storageClass="gp2"
```

The output from this command will give you the instructions for accessing the Prometheus UI from your local browser if you want.

**Install Grafana:**
- Create a seperate namespace:\
`kubectl create namespace grafana`
- Install it via Helm chart:
```
helm install grafana stable/grafana \
    --namespace grafana \
    --set persistence.storageClassName="gp2" \
    --set adminPassword='GrafanaAdm!n' \
    --set apiVersion=1 \
    --set name=Prometheus \
    --set type=prometheus \
    --set url=http://prometheus-server.prometheus.svc.cluster.local \
    --set access=proxy \
    --set isDefault=true \
    --set service.type=LoadBalancer
```

The output will give you the command to get the UI password.

Enter the LoadBalancer URL into your browser (`kubectl get svc -n grafana`) and login as `admin`.

**Steps to Import a Basic Dashboard into Grafana:**
- Go to https://grafana.com/grafana/dashboards for a list of pre-configured dashboards.
- Pick the ID of one you like (I searched for dashboards that use Prometheus as a source, and are K8s-based, and I got this: https://grafana.com/grafana/dashboards/10000)
- In Grafana > left-pane > + > Import > add the ID and set source to 'Prometheus' > Load.


#### Fargate on EKS
- Introduced at the end of 2019, Fargate is a container runtime for ECS/EKS, which enables "serverless Kubernetes". AWS manages the underlying infrastructure.
- You pay for pod-execution-time only. It is pricey.

You create a "Fargate Profile" (in YAML) where you specify an IAM role-arn (this allows the Fargate kubelet communicate w/your K8S API) and a namespace (since Fargate profiles are tied to a namespace), you also give it your VPC info so it knows where to spin up machine (under-the-hood).

There are limitations:
- Pods take longer to spin up.
- Limited RAM/CPU per pod.
- No support for Stateful workloads w/persistent volumes (yet).
- Available in select regions only.
- Only compatible with ALB.
- Can't run Daemonsets on it.

**How to Create a Fargate-enabled EKS Cluster**:\
This EKSCTL command requires a fargate profile. Create a YAML file with the following contents:
```
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: kag-test
  region: us-east-1

fargateProfiles:
  - name: demo
    selectors:
      - namespace: demo
  - name: staging
    selectors:
      - namespace: staging
        labels:
          env: staging
          checks: passed
```
- Run `eksctl create fargateprofile -f ./fargate-profile.yaml`




#### Cleanup
- Delete all provsioned resourced (`kubectl delete -f xxx.yml -n xxx`)
- `eksctl delete cluster -f eks-cluster.yml`
- The default storage class doesn't retain the EBS volumes so we don't have to manually clean-up anything (we would have to had we used our own SC or updated the policy to 'Retain')


#### Sources
- https://www.udemy.com/course/amazon-eks-starter-kubernetes-on-aws/
