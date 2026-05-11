variable "backup_vault_name" {
  description = "The name of the backup vault."
  default     = "default-backup-vault"
}

variable "backup_plan_name" {
  description = "The name of the backup plan."
  default     = "daily-backup-plan"
}

variable "backup_rule_name" {
  description = "The name of the backup rule."
  default     = "daily-backup-rule"
}

variable "schedule" {
  description = "The schedule in cron expression for backups."
  default     = "cron(0 12 *  ? *)"
}

variable "delete_after" {
  description = "Number of days after which backups are deleted."
  default     = 97
}

variable "cold_storage_after" {
  description = "Number of days after which backups are moved to cold storage."
  default     = 7
}

variable "selection_name" {
  description = "The name for resource selection."
  default     = "int-backup-selection"
}

variable "tag_key" {
  description = "The key for resource tagging."
  default     = "name"
}

variable "tag_value" {
  description = "The value for resource tagging."
  default     = "S3"
}

variable "role_name" {
  description = "The name of the IAM role for backups."
  default     = "backup-role"
}

variable "s3_backup_policy_arn" {
  description = "The arn of the IAM role policy."
  default     = "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Backup"
}

variable "s3_restore_policy_arn" {
  description = "The arn of the IAM role policy."
  default     = "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Restore"
}