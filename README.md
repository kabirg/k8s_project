# EKS Implementation Version 1
A demo to deploy a very simple EKS cluster with Terraform, and then deploy Metric Server and a K8S dashboard.

See README under ***eks_deployment*** directory for more information.

# EKS Implementation Version 2
A demo which utilizes Terraform Workspaces to deploy an EKS cluster within a multi-account strategy, with the state stored remotely. It will also add an NGINX Ingress (and requite DNS components for SSL-enablement), RBAC resources, and deploy a simple app via the Helm provider.

See README under ***eks_deployment_v2*** directory for more information.

# EKS Implementation Version 3
This demo utilize EKSCTL to create and operate a cluster. It will also demo how to install the Cluster AutoScaler, understand Control Plane logging and container metrics, authentication, installing Metric Server and a dashboard, how to deploy Stateless and Stateful applications into the cluster, how to setup Prometheus and Grafana, and how to leverage EKSCTL to spin up a Fargate-enabled EKS cluster.

See README under ***eks_deployment_v3*** directory for more information.
