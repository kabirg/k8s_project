# Namespace for our Applications
resource "kubernetes_namespace" "eks_namespaces" {
  for_each = toset(var.namespaces)

  metadata {
    annotations = {
      name = each.key
    }

    name = each.key
  }
}

# Create K8s Role for users that need developer-permissions
resource "kubernetes_cluster_role" "k8s_developers_role" {
  metadata {
    name = "k8s-developers-role"
  }

  rule {
    api_groups = ["*"]
    resources  = ["pods", "pods/log", "deployments", "ingresses", "services"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = ["*"]
    resources  = ["pods/exec"]
    verbs      = ["create"]
  }

  rule {
    api_groups = ["*"]
    resources  = ["pods/portforward"]
    verbs      = ["*"]
  }
}

# Bind role to developer IAM-users
resource "kubernetes_cluster_role_binding" "k8s_developers_rolebinding" {
  metadata {
    name = "k8s-developers-role"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "k8s-developers-role"
  }

  dynamic "subject" {
    for_each = toset(var.dev_users)

    content {
      name      = subject.key
      kind      = "User"
      api_group = "rbac.authorization.k8s.io"
    }
  }
}
