# EKS Implementation Version 2

This demo will deploy a simple VPC, EKS cluster, and then show how to manually (with kubectl) deploy Metric Server (to gather resource utilization metrics of our cluster) and a dashboard so that we can manage the cluster via internet browser.

## What Gets Deployed
***AWS Infrastructrure***
- Uses the official AWS VPC module from the Terraform Registry (https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest) to create the VPC with a user-supplied list of public and private subnets, all tagged with the required K8S tag. There is a single NAT Gateway in the public subnets.

***EKS***
- An EKS Cluster in the private subnets with a self-managed worker group.

## Instructions

***Create the AWS Accounts***
We need 3 AWS accounts.
- The 'main' account will host the Terraform state files.
- The 'development' account will be our sandbox account.
- The 'production' account will mimic a production environment where we'll promote infrastructure to.

***Tip:*** use your Gmail and append `+main`, `+development` and `+production`, to the email (ex: `kabirgupta3+main@gmail.com`). This lets you tie all accounts to your single Gmail account.

Create an IAM user in each account with programmatic access keys.

Create local profiles for each account. This will allow us to quickly switch between account credentials so our Terraform stack can build the resources in different accounts.

Command:\
`aws configure —profile <PROFILE_NAME>`
This will set the credentials in the local *~/.aws/credentials* & *~/.aws/config* files.

*Create the Terraform Backend Resources*
Here's Terraform template to build into our main/default account:
https://github.com/kabirg/terraform-s3-backend-setup/blob/main/main.tf

Run the following commands against it:
`terraform init`\
`terraform apply`

This will give us a centralized bucket to store all of our state files. I.e:
s3://kag-demo-terraform-state
|_env
  |_kag-development
  | |_tfstate.json
  |_kag-production
    |_tfstate.json

*Initialize the Stack*
CD back to our main EKS_v2 stack and run the following:
`terraform init -backend-config=backend.tfvars`

*Create Environment-specific Workspaces*
`terraform workspace new kag-development`
`terraform workspace new kag-production`

***Create the VPC***\
To run terraform stack, set your credentials (either as environment variables or in the AWS credentials file). Then run the following within the 'infrastructure' directory:\
`terraform init`\
`terraform apply`

Let's create our infrastructure in our development account.

Notice at the top of the `vpc.tf`:
`provider "aws" {
  region  = "us-east-1"
  profile = terraform.workspace
}`

By naming our workspaces after our AWS profiles, it allows us to select a specific workspace, and allow out stack to automatically deploy to the intended account.

Steps:
- Switch to development workspace, i.e `terraform workspace select kag-development`
- Run the terraform stack: `terraform apply --var-file=vpc-development.tfvars`

You'll now see the VPC in your development account, and the state file in the bucket of your main account.

***Create the EKS Cluster***\
Now we're adding in an *eks.tf*. Some things to note:
- We're creating a Kubernetes and Helm provider in this template since this is the base template for our EKS cluster. Neither of them are used in this particular template. But they will be used in subsequent templates when Terraform needs to authenticate into the cluster and provision stuff WITHIN it.
- We're using the official EKS terraform module (https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest) and creating a self-managed worker group.
- Authentication:
  - This time we're allowing EKS to create/manage the aws-auth file.
  - The aws-auth file is a config file within the cluster which simply states which IAM users have the ability to authenticate w/the cluster and what their RBAC permissions will be.
  - This means we have to create the IAM entities, the K8S roles and role-bindings, and then map them together within this aws-auth file.
  - We create admin/dev users in the local variables. These are created to allow the EKS module to create/pre-populate the aws-auth file on our behalf. They won't exist as physical IAM users yet but that's ok b/c K8s only check w/IAM when you actually try to authenticate).
  - Upon creation of the cluster, the last step (which we'll get to later) is to create out local KubeConfig file.
  - The cluster-creator (whichever IAM entity we're using to provision this Terraform stack) will automatically be given admin access to the cluster, this will not be visible within the AWS-Auth file though.

Steps:
- Switch to development workspace, i.e `terraform workspace select kag-development`
- Re-run `terraform init` b/c we have new providers that need to be downloaded.
- Run the terraform stack: `terraform apply --var-file=vpc-development.tfvars --var-file=eks-development.tfvars`

***Create the Ingress Load Balancer***\
You can publicly expose your K8s-hosted apps with a Service (of type 'LoadBalancer' in the cloud). But every service means a new costly load balancer. Ingress is an alternative that consolidates all routing through a single LB/service.

The NGINX Ingress Controller deploys an ALB in front of the services for your various apps. This ingres/ALB can then use "ingress resources" (aka routing rules) to send different traffic to different services.

Notes:
- To create a domain and add an SSL certificate, the *ingress.tf* template will:\
  - *Import a hosted zone (aws_route53_zone)* - I pre-registered a domain within ACM, which automatically created a Hosted Zone. An alternative is to purchase from an external registrar (like GoDaddy) and create the Hosted Zone in AWS rather than import. That method takes much longer to validate however, and it requires you to manually update the Namservers in the external registrar to match the AWS-provided NS's. Hence my decision to create the domain in ACM in advance.
  - *Request a cert from ACM (aws_acm_certificate)* - this will return a big CNAME.
  - *Create a record for that CNAME within the hosted zone (aws_route53_record/domain_cert_dns_validation)* - this is to facilitate ACM's "DNS Validation". Before ACM gives us our SSL cert, it validates that we own it by pinging the domain and verifying the CNAME is returned. Hence the need for us to create the CNAME record. This is quicker than the traditional email validation.
  - *Wait for cert to be issued (aws_acm_certificate_validation)* -
  - Useful source: https://www.grailbox.com/2020/04/how-to-set-up-a-domain-in-amazon-route-53-with-terraform/
- A Helm chart is used to deploy the NGINX Ingress.
  -
  - The NGINX Ingress Controller will create a Load Balancer. An Alias record with our domain will be applied to the LB.

***Create K8S Namespace and RBAC Resources***:\
Re-run the `terraform apply` with the *resources.tf* included. This template will create a Kubernetes Namespace for our apps, and it will create the K8S RBAC resources needed to limit the permission-scope for any dev users (who've already been mapped in AWS-Auth).

***Configure Kubectl with the Cluster's Access Credentials***:\
Run the following:\
`aws eks update-kubeconfig --region us-east-1 --name kag-eks-cluster --profile <PROFILE_NAME>`

You should get a response similar to this:\
`Updated context <CLUSTER_ARN> in /Users/kgupta/.kube/config`

You can now run kubectl commands in your cluster:\
`kubectl config current-context`

***Manually Deploy a Sample App (via Helm Chart) into the Cluster***:\
Ensure you have Helm v3 installed locally.

Run the following:
`helm upgrade --install sample-app --namespace sample-apps sample-app --values sample-app/values.yaml`

Access the application in your browser.


***Tips:***\
Deleting the cluster:
`terraform state rm module.my-cluster.kubernetes_config_map.a`

***Sources***\
- https://itnext.io/build-an-eks-cluster-with-terraform-d35db8005963#_=_
- https://rharshad.com/aws-eks-cluster-setup-part-1/
