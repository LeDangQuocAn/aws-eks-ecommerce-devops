# Module: elk
# Deploys Elasticsearch, Kibana, Logstash, and Fluent Bit into a dedicated
# logging namespace.

resource "kubernetes_namespace" "logging" {
  metadata {
    name = var.namespace
    labels = {
      name = var.namespace
    }
  }
}

resource "kubernetes_service_account" "kibana_hook_cleanup" {
  metadata {
    name      = "kibana-hook-cleanup"
    namespace = kubernetes_namespace.logging.metadata[0].name
  }
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
}

resource "helm_release" "elasticsearch" {
  name             = "elasticsearch"
  repository       = "https://helm.elastic.co"
  chart            = "elasticsearch"
  namespace        = kubernetes_namespace.logging.metadata[0].name
  create_namespace = false
  timeout          = 3600
  atomic           = true

  values = [file("${path.module}/elk-values/elasticsearch-values.yaml")]

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

  values = [file("${path.module}/elk-values/kibana-values.yaml")]

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

  values = [file("${path.module}/elk-values/logstash-values.yaml")]

  depends_on = [helm_release.elasticsearch]
}

resource "helm_release" "fluent_bit" {
  name             = "fluent-bit"
  repository       = "https://fluent.github.io/helm-charts"
  chart            = "fluent-bit"
  namespace        = kubernetes_namespace.logging.metadata[0].name
  create_namespace = false
  timeout          = 1200
  atomic           = true
  cleanup_on_fail  = true
  replace          = true
  wait_for_jobs    = true

  values = [file("${path.module}/elk-values/fluent-bit-values.yaml")]

  depends_on = [helm_release.logstash]
}
