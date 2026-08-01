data "aws_iam_policy_document" "master_secret" {
  statement {
    sid    = "RestrictSecretAccess"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = [
      "secretsmanager:GetSecretValue"
    ]

    resources = [
      aws_rds_cluster.this.master_user_secret[0].secret_arn
    ]

    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values   = var.secret_allowed_principal_arns
    }
  }
}

resource "aws_secretsmanager_secret_policy" "master" {
  secret_arn = aws_rds_cluster.this.master_user_secret[0].secret_arn
  policy     = data.aws_iam_policy_document.master_secret.json

  block_public_policy = true
}