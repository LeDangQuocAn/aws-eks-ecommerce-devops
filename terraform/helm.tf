# ─── AWS Load Balancer Controller ────────────────────────────────────────────
# Watches Ingress and Service resources and provisions ALB/NLB on AWS.
# Required for exposing the UI microservice through an Application Load Balancer.

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  # Pin to a tested version; update after checking compatibility with EKS 1.34
  version = "1.10.0"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  # Service account is created by the chart; the annotation binds it to the IRSA role
  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.eks.aws_lbc_role_arn
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = module.vpc.output_vpc_id
  }

  depends_on = [module.eks]
}

# ─── Cluster Autoscaler ───────────────────────────────────────────────────────
# Scales node groups up when pods are pending due to insufficient resources
# and scales down when nodes are underutilised.

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  # Pin to a tested version; must match the major.minor of the Kubernetes version
  version = "9.43.0"

  set {
    name  = "autoDiscovery.clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "awsRegion"
    value = var.aws_region
  }

  # Service account with IRSA annotation
  set {
    name  = "rbac.serviceAccount.create"
    value = "true"
  }

  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }

  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.eks.cluster_autoscaler_role_arn
  }

  # Prevent the autoscaler from evicting itself
  set {
    name  = "podDisruptionBudget.maxUnavailable"
    value = "1"
  }

  depends_on = [module.eks]
}

# ─── Monitoring: Prometheus + Grafana (kube-prometheus-stack) ───────────────
# Deploy a curated Prometheus + Alertmanager + Grafana stack into the cluster

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      name = "monitoring"
    }
  }

  depends_on = [module.eks]
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  # Pin to a tested version; update as needed when upgrading
  version = "45.6.0"

  # Expose Grafana via LoadBalancer so it is accessible for demos.
  set {
    name  = "grafana.service.type"
    value = "LoadBalancer"
  }

  # Create service accounts inside the chart (IRSA can be added later if required)
  set {
    name  = "prometheus.serviceAccount.create"
    value = "true"
  }

  set {
    name  = "grafana.serviceAccount.create"
    value = "true"
  }

  set {
    name  = "grafana.adminPassword"
    value = "admin"
  }

  set {
    name  = "grafana.adminUser"
    value = "admin"
  }

  # Keep the deployment tied to cluster creation
  depends_on = [module.eks]
}

# ─── ELK Stack (Elasticsearch + Kibana + Logstash) ──────────────────────────
# Managed through the Terraform Helm provider so the release lifecycle stays in
# the same state as the rest of the cluster add-ons.

resource "kubernetes_namespace" "logging" {
  metadata {
    name = "logging"
    labels = {
      name = "logging"
    }
  }

  depends_on = [module.eks]
}

resource "kubernetes_service_account" "kibana_hook_cleanup" {
  metadata {
    name      = "kibana-hook-cleanup"
    namespace = kubernetes_namespace.logging.metadata[0].name
  }

  depends_on = [kubernetes_namespace.logging]
}

resource "kubernetes_role" "kibana_hook_cleanup" {
  metadata {
    name      = "kibana-hook-cleanup"
    namespace = kubernetes_namespace.logging.metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps", "secrets", "serviceaccounts", "pods", "jobs"]
    verbs      = ["get", "list", "delete", "deletecollection"]
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs"]
    verbs      = ["get", "list", "delete", "deletecollection"]
  }

  rule {
    api_groups = ["rbac.authorization.k8s.io"]
    resources  = ["roles", "rolebindings"]
    verbs      = ["get", "list", "delete", "deletecollection"]
  }

  depends_on = [kubernetes_namespace.logging]
}

resource "kubernetes_role_binding" "kibana_hook_cleanup" {
  metadata {
    name      = "kibana-hook-cleanup"
    namespace = kubernetes_namespace.logging.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.kibana_hook_cleanup.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.kibana_hook_cleanup.metadata[0].name
    namespace = kubernetes_namespace.logging.metadata[0].name
  }

  depends_on = [kubernetes_role.kibana_hook_cleanup]
}

resource "kubernetes_job_v1" "kibana_hook_cleanup" {
  metadata {
    name      = "kibana-hook-cleanup"
    namespace = kubernetes_namespace.logging.metadata[0].name
  }

  spec {
    backoff_limit = 0

    template {
      metadata {
        name = "kibana-hook-cleanup"
      }

      spec {
        service_account_name = kubernetes_service_account.kibana_hook_cleanup.metadata[0].name
        restart_policy       = "Never"

        container {
          name              = "delete-secret"
          image             = "registry.k8s.io/kubectl:v1.34.1"
          image_pull_policy = "IfNotPresent"
          command           = ["kubectl"]
          args              = ["delete", "secret", "-n", "logging", "kibana-app-es-token", "--ignore-not-found"]
        }

        container {
          name              = "delete-configmap"
          image             = "registry.k8s.io/kubectl:v1.34.1"
          image_pull_policy = "IfNotPresent"
          command           = ["kubectl"]
          args              = ["delete", "configmap", "-n", "logging", "kibana-app-helm-scripts", "--ignore-not-found"]
        }

        container {
          name              = "delete-serviceaccounts"
          image             = "registry.k8s.io/kubectl:v1.34.1"
          image_pull_policy = "IfNotPresent"
          command           = ["kubectl"]
          args              = ["delete", "sa", "-n", "logging", "pre-install-kibana-app", "post-delete-kibana-app", "--ignore-not-found"]
        }

        container {
          name              = "delete-roles"
          image             = "registry.k8s.io/kubectl:v1.34.1"
          image_pull_policy = "IfNotPresent"
          command           = ["kubectl"]
          args              = ["delete", "role", "-n", "logging", "pre-install-kibana-app", "post-delete-kibana-app", "--ignore-not-found"]
        }

        container {
          name              = "delete-rolebindings"
          image             = "registry.k8s.io/kubectl:v1.34.1"
          image_pull_policy = "IfNotPresent"
          command           = ["kubectl"]
          args              = ["delete", "rolebinding", "-n", "logging", "pre-install-kibana-app", "post-delete-kibana-app", "--ignore-not-found"]
        }

        container {
          name              = "delete-jobs"
          image             = "registry.k8s.io/kubectl:v1.34.1"
          image_pull_policy = "IfNotPresent"
          command           = ["kubectl"]
          args              = ["delete", "job", "-n", "logging", "pre-install-kibana-app", "post-delete-kibana-app", "--ignore-not-found"]
        }

        container {
          name              = "delete-pre-install-pods"
          image             = "registry.k8s.io/kubectl:v1.34.1"
          image_pull_policy = "IfNotPresent"
          command           = ["kubectl"]
          args              = ["delete", "pod", "-n", "logging", "-l", "job-name=pre-install-kibana-app", "--ignore-not-found"]
        }

        container {
          name              = "delete-post-delete-pods"
          image             = "registry.k8s.io/kubectl:v1.34.1"
          image_pull_policy = "IfNotPresent"
          command           = ["kubectl"]
          args              = ["delete", "pod", "-n", "logging", "-l", "job-name=post-delete-kibana-app", "--ignore-not-found"]
        }

        container {
          name              = "delete-kibana-pods"
          image             = "registry.k8s.io/kubectl:v1.34.1"
          image_pull_policy = "IfNotPresent"
          command           = ["kubectl"]
          args              = ["delete", "pod", "-n", "logging", "-l", "release=kibana", "--ignore-not-found"]
        }
      }
    }
  }

  depends_on = [
    kubernetes_service_account.kibana_hook_cleanup,
    kubernetes_role_binding.kibana_hook_cleanup,
  ]
}

resource "helm_release" "elasticsearch" {
  name             = "elasticsearch"
  repository       = "https://helm.elastic.co"
  chart            = "elasticsearch"
  namespace        = kubernetes_namespace.logging.metadata[0].name
  create_namespace = false
  timeout          = 3600
  atomic           = true

  values = [file("${path.module}/modules/elk/elk-values/elasticsearch-values.yaml")]

  depends_on = [kubernetes_namespace.logging]
}

resource "helm_release" "kibana" {
  name             = "kibana"
  repository       = "https://helm.elastic.co"
  chart            = "kibana"
  namespace        = kubernetes_namespace.logging.metadata[0].name
  create_namespace = false
  timeout          = 2400
  atomic           = true
  cleanup_on_fail  = true
  replace          = true
  wait_for_jobs    = true

  values = [file("${path.module}/modules/elk/elk-values/kibana-values.yaml")]

  depends_on = [helm_release.elasticsearch, kubernetes_job_v1.kibana_hook_cleanup]
}

resource "helm_release" "logstash" {
  name             = "logstash"
  repository       = "https://helm.elastic.co"
  chart            = "logstash"
  namespace        = kubernetes_namespace.logging.metadata[0].name
  create_namespace = false
  timeout          = 1200
  atomic           = true

  values = [file("${path.module}/modules/elk/elk-values/logstash-values.yaml")]

  depends_on = [helm_release.elasticsearch]
}
