variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_autoscaler_role_arn" {
  description = "IRSA role ARN for the Cluster Autoscaler"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "chart_version" {
  description = "Pinned chart version"
  type        = string
  default     = "9.43.0"
}