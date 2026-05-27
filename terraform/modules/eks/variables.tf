variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.35"
}

variable "vpc_id" {
  description = "ID of the VPC where the EKS cluster will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EKS worker nodes (one per AZ)"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs (used for public-facing load balancers)"
  type        = list(string)
}

variable "access_entries" {
  description = "Map of EKS access entries to add to the cluster"
  type        = any
  default     = {}
}

variable "enable_cluster_creator_admin_permissions" {
  description = "Whether to add the cluster creator identity as a cluster admin via access entry"
  type        = bool
  default     = true
}

variable "node_group_instance_type" {
  description = "EC2 instance type override for AZ1 node group"
  type        = string
  default     = "t3.medium"
}

variable "node_group_az1_min_size" {
  description = "Minimum nodes for AZ1 node group"
  type        = number
  default     = 1
}

variable "node_group_az2_min_size" {
  description = "Minimum nodes for AZ2 node group"
  type        = number
  default     = 0
}

variable "node_group_az1_max_size" {
  description = "Maximum nodes for AZ1 node group"
  type        = number
  default     = 10
}

variable "node_group_az2_max_size" {
  description = "Maximum nodes for AZ2 node group"
  type        = number
  default     = 6
}

variable "node_group_az1_desired_size" {
  description = "Desired nodes for AZ1 node group"
  type        = number
  default     = 8
}

variable "node_group_az2_desired_size" {
  description = "Desired nodes for AZ2 node group"
  type        = number
  default     = 0
}

variable "tags" {
  description = "Common tags to apply to all resources created by this module"
  type        = map(string)
  default     = {}
}
