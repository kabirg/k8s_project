# EKS Implementation Version 1

This demo will deploy a simple VPC, EKS cluster, and then show how to manually (with kubectl) deploy Metric Server (to gather resource utilization metrics of our cluster) and a dashboard so that we can manage the cluster via internet browser.

## What Gets Deployed
***VPC***
- A single VPC with a custom CIDR.
- The VPC and subnets are tagged with the required EKS tag ("kubernetes.io/cluster/{eks_cluster_name} = shared")
  - https://docs.aws.amazon.com/eks/latest/userguide/network_reqs.html
  - Theoretically it shouldn't be required anymore since I'm building a cluster w/version 1.17
- The stack accepts a list of public and private subnet-CIDR's, loops through them and builds them in a list of available AZ's.
  - The public RT is associated with each public subnet.
- A NAT Gateway is placed in a public subnet and each private subnet gets external access through that.

***EKS***
- The EKS cluster is built using the official EKS module from the Terraform registry: https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest
- Node Group
  - Managed by AWS (as opposed to self-managed workder groups).
  - We spin this up within an ASG that spans our private subnets.
- Authentication
  - "manage_aws_auth" configures the aws-auth ConfigMap. This map is used by the EKS cluster to grant IAM users/roles RBAC permissions within the cluster (not the same as the IAM roles on the nodes themselves).
  - If true (which is the default), Terraform will need access to the K8S API to manage the CM on our behalf.
  - We set it to false, which lets us manage it ourselves.
  - We will access the cluster with the same user that we used to spin up the cluster (this user by default gets system:master RBAC permissions; additional users have to be added to the aws-auth config-map).

## Instructions

***Apply the Terraform Stack***\
To run terraform stack, set your credentials (either as environment variables or in the AWS credentials file). Then run the following within the 'infrastructure' directory:\
`terraform init`\
`terraform apply`

***Configure Kubectl with the Cluster's Access Credentials***:\
Run the following:\
`aws eks update-kubeconfig --region us-east-1 --name my_eks_infra`

You should get a response similar to this:\
`Updated context <CLUSTER_ARN> in /Users/kgupta/.kube/config`

You can now run kubectl commands in your cluster:\
`kubectl config current-context`

***Deploy Metric Server***\
Metrics Server is an open-source monitoring tool which can retrieve pod-level metrics from the kubelet API (Kubelet contains cAdvisor which exposes these metrics through the API).

Since we kept our Terraform stack light and didn't add a kubernets provider (which would allow us to provision resources WITHIN the cluster with Terraform, not just the cluster itself), we will do this manually with kubectl.

- Install and unzip the Metrics Server package:\
  `wget -O v0.3.6.tar.gz https://codeload.github.com/kubernetes-sigs/metrics-server/tar.gz/v0.3.6 && tar -xzf v0.3.6.tar.gz`
- Deploy it to the cluster:\
  `kubectl apply -f metrics-server-0.3.6/deploy/1.8+/`
- Verify it was deployed:\
  `kubectl get deployment metrics-server -n kube-system`\
  `kubectl top pod`

***Deploy K8S Dashboard***\
Run the following:\
`kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-beta8/aio/deploy/recommended.yaml`

***Access the Dashboard***\
In order to access API with an HTTP client like a web browser, we can run kubectl in a mode where it acts like a reverse proxy between our local workstation and the API server. Kubectl will take care of location and authenticating to the server.
- Retrieve the cluster authentication token with this command:\
  `kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep service-controller-token | awk '{print $1}')`
- Start the proxy: `kubectl proxy`
- Access this URL from a browser:\
`http://127.0.0.1:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy`
- Enter the token when prompted. We could also create a separate Service Account and use it's token at this point instead.

***Sources:***
- https://adrian-philipp.com/notes/use-the-terraform-eks-module-without-kubernetes-access
- https://github.com/terraform-aws-modules/terraform-aws-eks/blob/master/docs/faq.md
- https://docs.aws.amazon.com/eks/latest/userguide/add-user-role.html
- https://medium.com/edureka/kubernetes-dashboard-d909b8b6579c
