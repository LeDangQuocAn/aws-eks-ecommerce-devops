variable "namespace" {
  description = "Kubernetes namespace for the monitoring stack"
  type        = string
}

variable "grafana_admin_user" {
  description = "Grafana admin username"
  type        = string
  default     = "admin"
}

variable "grafana_admin_pass" {
  description = "Grafana admin password"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "kube_prom_stack_ver" {
  description = "Pinned kube-prometheus-stack chart version"
  type        = string
  default     = "45.6.0"
}
