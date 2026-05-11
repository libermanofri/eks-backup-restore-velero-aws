resource "aws_backup_vault" "default" {
  name = var.backup_vault_name
}

resource "aws_backup_plan" "daily_backup" {
  name = var.backup_plan_name

  rule {
    rule_name         = var.backup_rule_name
    target_vault_name = aws_backup_vault.default.name
    schedule          = var.schedule

    lifecycle {
      delete_after       = var.delete_after
      cold_storage_after = var.cold_storage_after
    }
  }
}

resource "aws_backup_selection" "backup_resources" {
  name         = var.selection_name
  iam_role_arn = aws_iam_role.backup_role.arn
  plan_id      = aws_backup_plan.daily_backup.id

  selection_tag {
    type  = "STRINGEQUALS"
    key   = var.tag_key
    value = var.tag_value
  }
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "backup_role" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "backup_policy_attach" {
  role       = var.role_name
  policy_arn = var.s3_backup_policy_arn
}

resource "aws_iam_role_policy_attachment" "restore_policy_attach" {
  role       = var.role_name
  policy_arn = var.s3_restore_policy_arn
}