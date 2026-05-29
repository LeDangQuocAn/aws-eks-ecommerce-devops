# ─── Monitoring: Prometheus + Grafana ────────────────────────────────────────
module "monitoring" {
  source = "./modules/monitoring"

  namespace           = "monitoring"
  grafana_admin_user  = "admin"
  grafana_admin_pass  = "admin"
  kube_prom_stack_ver = "45.6.0"

  depends_on = [module.eks]
}

# ─── AWS Load Balancer Controller ────────────────────────────────────────────
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name     = module.eks.cluster_name
  aws_lbc_role_arn = module.eks.aws_lbc_role_arn
  aws_region       = var.aws_region
  vpc_id           = module.vpc.output_vpc_id

  depends_on = [module.eks]
}

# ─── Cluster Autoscaler ───────────────────────────────────────────────────────
module "cluster_autoscaler" {
  source = "./modules/cluster_autoscaler"

  cluster_name                = module.eks.cluster_name
  cluster_autoscaler_role_arn = module.eks.cluster_autoscaler_role_arn
  aws_region                  = var.aws_region

  depends_on = [module.eks]
}

# ─── ELK Stack ───────────────────────────────────────────────────────────────
module "elk" {
  source = "./modules/elk"

  namespace = "logging"

  depends_on = [module.eks]
}
