variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "aws_lbc_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID used by the controller"
  type        = string
}

variable "chart_version" {
  description = "Pinned chart version"
  type        = string
  default     = "1.10.0"
}