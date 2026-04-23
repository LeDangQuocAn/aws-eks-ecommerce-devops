module "this" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = var.role_name

  attach_load_balancer_controller_policy = var.attach_load_balancer_controller_policy
  attach_ebs_csi_policy                  = var.attach_ebs_csi_policy
  attach_cluster_autoscaler_policy       = var.attach_cluster_autoscaler_policy
  cluster_autoscaler_cluster_names       = var.cluster_autoscaler_cluster_names

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = var.namespace_service_accounts
    }
  }

  tags = var.tags
}

data "aws_iam_policy_document" "ecr_create" {
  count = var.attach_ecr_create_policy ? 1 : 0

  statement {
    sid = "EcrCreateAndConfigureRepositories"

    actions = [
      "ecr:CreateRepository",
      "ecr:DescribeRepositories",
      "ecr:PutLifecyclePolicy",
      "ecr:PutImageScanningConfiguration",
      "ecr:PutImageTagMutability",
      "ecr:SetRepositoryPolicy",
      "ecr:TagResource"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "ecr_create" {
  count = var.attach_ecr_create_policy ? 1 : 0

  name        = "${var.role_name}-ecr-create"
  description = "Allows creating and configuring ECR repositories"
  policy      = data.aws_iam_policy_document.ecr_create[0].json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecr_create" {
  count = var.attach_ecr_create_policy ? 1 : 0

  role       = module.this.iam_role_name
  policy_arn = aws_iam_policy.ecr_create[0].arn
}
