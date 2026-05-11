# EKS Backup and Disaster Recovery with Velero and AWS Backup

## Overview
The project focuses on creating a reliable **backup and restore solution** for an **Amazon EKS (Elastic Kubernetes Service)** cluster using **Velero** and **AWS Backup**. The goal was to design and automate a backup mechanism for Kubernetes resources and persist them to **Amazon S3**. We also explored recovery strategies to restore workloads seamlessly without downtime.

This project demonstrates our understanding of cloud-native tools, infrastructure-as-code (IaC) principles, and backup automation.

---

## Project Goals
1. Automate backups for Kubernetes workloads using **Velero** and store them on **S3**.
2. Use **AWS Backup** to create recovery points for S3 and EKS data.
3. Restore Kubernetes resources to a previous state after data loss or failure.
4. Implement Terraform for infrastructure provisioning and automation.
5. Test and validate backup/restore processes under different scenarios.

---

## Tools & Technologies Used
- **Terraform**: Infrastructure-as-Code (IaC) to provision EKS, S3 buckets, and IAM roles.
- **Velero**: A Kubernetes-native tool for backup and recovery of resources and persistent volumes.
- **AWS Backup**: Native AWS service for centralized backup management.
- **AWS CLI**: Command-line interface to interact with AWS services.
- **Amazon S3**: Storage for Velero backups and AWS Backup recovery points.
- **Kubernetes**: Container orchestration system for workload management.
- **Helm**: Kubernetes package manager used to deploy Velero.
- **AWS IAM**: Role-based access control for Velero and AWS Backup services.
- **kubectl**: Command-line tool for Kubernetes cluster management.

---

## Architecture Overview
The architecture includes:

1. **Terraform for provisioning**:
   - S3 bucket with lifecycle rules for cold storage and expiration.
2. **IAM roles and policies** for AWS Backup and Velero integration.
3. **Velero** for managing backups of Kubernetes resources and storing backups in S3.
4. **AWS Backup** for automated daily backups.
5. Data Recovery using `aws s3 sync` to move data between buckets.

---

## What We Learned
1. **Kubernetes Backup Concepts**: How to back up Kubernetes namespaces, pods, and volumes.
2. **Velero Configuration**: Managing `BackupStorageLocations`, schedules, and restores.
3. **AWS Backup**: Creating backup plans, vaults, and recovery points.
4. **Terraform**: Automating the provisioning of S3 buckets, IAM roles, and Kubernetes Helm deployments.
5. **Troubleshooting**: Diagnosing issues with IAM permissions, failed backups, and restore processes.

---

## Challenges Faced
1. **IAM Permissions Issues**:
   - Ensuring Velero and AWS Backup roles had the correct permissions for `s3:ListBucket`, `sts:AssumeRole`, and other actions.
2. **Storage Misconfigurations**:
   - Velero backups initially saved to incorrect buckets due to misconfigured `BackupStorageLocation`.
3. **Cluster Resource Conflicts**:
   - During restore, existing resources conflicted with backups, requiring additional resource policies.
4. **Automation**:
   - Ensuring Terraform managed all resources end-to-end seamlessly.

---

## Setup and Configuration

### 1. **Provision S3 Bucket with Terraform**
Provision an S3 bucket with lifecycle rules to expire data after 30 days and move to Glacier after 7 days.

<code>main.tf</code>

**Terraform Code**:
```
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket = "eks-velero-backup-bucket"
  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"
  acl    = "private"

  versioning = {
    enabled = true
  }

  lifecycle_rule = [
    {
      id      = "transition_to_glacier"
      enabled = true

      filter = {
        prefix = "" # Applies to all objects
      }

      expiration = {
        days = 30 # Delete objects after 30 days
      }

      transition = {
        days          = 7
        storage_class = "GLACIER"
      }
    }
  ]

  tags = {
    aws_backup = true
  }
}
```
Run Terraform:
```bash
terraform init
terraform plan
terraform apply
```

### 2. Backup S3 Bucket Using AWS Backup

1. Create an AWS Backup Vault and a backup plan using Terraform.

We use a selection tag to dynamically select resources that should be backed up. Resources with the tag `aws_backup=true` are included in the backup plan.

<code>backup.tf:</code>

```hcl
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
```

Commands:

- Deploy the plan:
```bash
terraform apply
```
- Verify backup jobs under AWS Backup > Jobs in the AWS Management Console.

### 3. **Restore S3 Bucket Using AWS CLI**

If your S3 bucket is deleted or needs recovery, you can restore it from AWS Backup.

### Step 1: Start Restore Job

Run the following command to restore the S3 bucket to a new bucket:

```bash
aws backup start-restore-job \
  --recovery-point-arn <Recovery-Point-ARN> \
  --metadata '{"newBucketName":"restored-ofri-s3"}' \
  --iam-role-arn arn:aws:iam::<account_id>:role/<role-name> \
  --resource-type S3 \
  --region <region>
```

Replace:

- `<Recovery-Point-ARN>`: ARN of the recovery point.
- `<account_id>`: Your AWS account ID.
- `<role-name>`: IAM role for AWS Backup.
- `<region>`: Region of your S3 bucket.

### Step 2: Sync Data Back to Original Bucket

If you need to **restore data** back to the original bucket:

```bash
aws s3 sync s3://restored-ofri-s3 s3://eks-velero-backup-bucket --region us-east-2
```
Verify the data:
```bash
aws s3 ls s3://eks-velero-backup-bucket --recursive --region us-east-2
```

---

### 4. **Install Velero Using Helm**

We used a Terraform module to install Velero with Helm.

**Helm Configuration with Terraform**:

```hcl
module "velero" {
  source  = "terraform-module/release/helm"
  version = "2.6.0"

  namespace  = "velero-ofri"
  repository = "https://vmware-tanzu.github.io/helm-charts"

  app = {
    name          = "velero"
    version       = "8.0.0"
    chart         = "velero"
    force_update  = true
    wait          = false
    recreate_pods = false
    deploy        = 1
  }

  values = [
    templatefile("${path.module}/values/velero.yaml", {
      region               = "us-east-2"
      bucket_name          = "eks-velero-backup-bucket"
      velero_role_arn      = module.velero_irsa_role.iam_role_arn
    })
  ]

  set = [
    {
      name  = "serviceAccount.server.create"
      value = "true"
    },
    {
      name  = "serviceAccount.server.name"
      value = "velero"
    }
  ]
}
```

---

### 5. **Configure IAM Role for Velero**

To allow Velero to back up and restore resources in your Kubernetes cluster and store data in S3, we configured an **IAM Role for Service Accounts (IRSA)** using Terraform. This ensures secure and scoped permissions for Velero.

#### Terraform Code:

```hcl
module "velero_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name             = "velero"
  attach_velero_policy  = true
  velero_s3_bucket_arns = ["arn:aws:s3:::eks-velero-backup-bucket"]

  oidc_providers = {
    eks_oidc = {
      provider_arn               = "arn:aws:iam::023196572641:oidc-provider/${local.sliced_url}"
      namespace_service_accounts = ["velero-ofri:velero"]
    }
  }

  tags = {
    Createdby = "OFRI"
  }
}
```

#### Explanation of `locals` and `sliced_url`:

In the Terraform configuration, we used a `locals` block to extract and format the OIDC issuer URL from the EKS cluster:

```hcl
locals {
  original_url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
  sliced_url   = replace(local.original_url, "https://", "")
}
```

**What does this do?**
1. `original_url`: Fetches the full OIDC issuer URL from the EKS cluster metadata.
   - Example: `https://oidc.eks.us-east-2.amazonaws.com/id/EXAMPLE12345`
2. `sliced_url`: Removes the `https://` prefix from the URL using the `replace` function.
   - Example: `oidc.eks.us-east-2.amazonaws.com/id/EXAMPLE12345`

This processed URL is necessary to define the OIDC provider ARN for the IAM role, as AWS expects it in this format.

#### Key Highlights:
- **attach_velero_policy**: Automatically attaches the predefined Velero policy for S3 access.
- **velero_s3_bucket_arns**: Specifies the bucket ARN for Velero backups.
- **oidc_providers**: Configures the OIDC provider for your EKS cluster to enable IRSA.

#### Benefits of IRSA:
1. Fine-grained access control.
2. No need to manage long-term credentials for Velero.
3. Enhanced security by scoping permissions to specific namespaces and service accounts.

#### Verification:

After applying the Terraform configuration, you can verify the IAM role and its association with Velero:

1. **Check IAM Role Creation:**
   ```bash
   aws iam get-role --role-name velero
   ```

2. **Check the OIDC Provider:**
   ```bash
   aws eks describe-cluster --name <cluster-name> --query "cluster.identity.oidc.issuer"
   ```

3. **Ensure the Service Account is Associated:**
   ```bash
   kubectl get serviceaccount velero -n velero-ofri -o yaml
   ```

#### Role in Helm Chart:

The created IAM role is referenced in the Velero Helm chart to associate it with the Velero service account. This ensures Velero uses the correct permissions when interacting with S3.

---


## Cron Job Scheduling
We configured Velero to perform hourly backups using a cron schedule:

```yaml
schedules:
  hourly-backup:
    schedule: "0 * * * *"
    template:
      ttl: 90m
      includedNamespaces:
        - "ofri-nginx"
```

Apply the configuration:
```bash
kubectl apply -f values/velero.yaml
```

---

### Explaining IRSA ###

**What is IRSA?**

IRSA stands for IAM Roles for Service Accounts. It’s a mechanism provided by AWS that allows applications running in Kubernetes pods to securely access AWS resources without needing hardcoded credentials or access keys.

Think of IRSA as a bridge between Kubernetes service accounts (used within the cluster) and AWS IAM roles (used to manage permissions for AWS resources).

**Here’s how it works:**

1. When a pod runs in Kubernetes, it uses a service account.
2. With IRSA, we link that service account to an IAM role.
3. The pod automatically gets temporary credentials through AWS's OIDC provider, allowing it to access AWS resources like S3 or DynamoDB securely.

**Why Did We Use IRSA?**
We used IRSA to give Velero (a Kubernetes application) permissions to access AWS S3 buckets. Velero needs access to the S3 bucket for storing and retrieving backups. Without IRSA, we would have to use less secure methods, like:

- Hardcoding AWS credentials in the Velero configuration.
- Using shared secrets or static credentials.

**IRSA solves this by:**

- Improving security: No need for hardcoded credentials in the cluster.
- Simplifying management: Each pod can get unique permissions based on the role attached to its service account.
- Automating credentials: AWS generates and rotates temporary credentials for the pod automatically.

**How Does IRSA Work in Our Project?**

**1. OIDC Provider:**
Kubernetes uses the OpenID Connect (OIDC) protocol to communicate with AWS. This is why we configured the OIDC provider for our EKS cluster.

**2. Service Account to IAM Role Mapping:**
We created an IAM role (velero role) with the required permissions (like access to S3).
We annotated the Velero service account to use this IAM role.

**3. Temporary Credentials:**
When Velero runs in a pod, AWS provides it with temporary credentials through the OIDC provider, allowing it to securely access the S3 bucket.

**Why is IRSA Better Than Other Approaches?**

1. No Static Keys: With IRSA, there’s no need to store AWS keys in the cluster or code.
2. Granular Permissions: Each service account can have different IAM roles and permissions.
3. Scalable: As your cluster grows, you can manage access for different workloads more easily.

**Simple Analogy**

Think of IRSA as giving your Kubernetes pods temporary visitor passes to access specific areas (AWS resources) in a building (AWS environment). Instead of giving everyone a permanent key to all rooms, you give them a pass that works only for the rooms they need and expires automatically.

---

## Commands Cheat Sheet

| **Action**                                     | **Command**                                                                                                                                                                                                                              |
|-----------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Start Restore Job**                          | `aws backup start-restore-job --recovery-point-arn <recovery-point-arn> --iam-role-arn <iam-role-arn> --metadata '{"newBucketName":"<new-bucket-name>","encrypted":"false","creationToken":"<unique-creation-token>"}'`                   |
| **List Recovery Points in Backup Vault**      | `aws backup list-recovery-points-by-backup-vault --backup-vault-name <backup-vault-name>`                                                                                                                                                 |
| **List Backup Jobs**                           | `aws backup list-backup-jobs`                                                                                                                                                                                                            |
| **List Restore Jobs**                          | `aws backup list-restore-jobs`                                                                                                                                                                                                           |
| **Describe Restore Job**                      | `aws backup describe-restore-job --restore-job-id <restore-job-id>`                                                                                                                                                                      |
| **Sync Data Between Buckets**                 | `aws s3 sync s3://<source-bucket> s3://<target-bucket> --region <region>`                                                                                                                                                                |
| **Remove S3 Bucket**                          | `aws s3 rb s3://<bucket-name> --force`                                                                                                                                                                                                   |
| **Check Backup Storage Location**             | `kubectl get backupstoragelocation -n <namespace>`                                                                                                                                                                                       |
| **Describe Backup Storage Location**          | `kubectl describe backupstoragelocations.velero.io <name> -n <namespace>`                                                                                                                                                                |
| **View All Resources in Namespace**           | `kubectl get all -n <namespace>`                                                                                                                                                                                                         |
| **Install Velero with Default Values**        | `helm upgrade --install velero vmware-tanzu/velero -f values/velero.yaml -n <namespace>`                                                                                                                                                 |
| **Install Velero with Service Account**       | `helm upgrade --install velero vmware-tanzu/velero --namespace <namespace> --set serviceAccount.server.create=true --set serviceAccount.server.name=velero --set serviceAccount.server.annotations."eks\\.amazonaws\\.com/role-arn"=<role-arn> -f ./values/velero.yaml --force` |
| **Uninstall Velero**                          | `helm uninstall velero --namespace <namespace>`                                                                                                                                                                                          |
| **View Helm History**                         | `helm history velero --namespace <namespace>`                                                                                                                                                                                            |
| **Rollback Helm Release**                     | `helm rollback velero --namespace <namespace>`                                                                                                                                                                                           |
| **Velero Backup**                             | `velero backup create <backup-name> --include-namespaces <namespace>`                                                                                                                                                                    |
| **List Velero Backups**                       | `velero backup get`                                                                                                                                                                                                                      |
| **Describe Velero Backup**                   | `velero backup describe <backup-name> --details`                                                                                                                                                                                         |
| **Velero Restore**                            | `velero restore create --from-backup <backup-name>`                                                                                                                                                                                      |
| **Describe Velero Restore**                  | `velero restore describe <restore-name>`                                                                                                                                                                                                 |
| **View Velero Restore Logs**                  | `velero restore logs <restore-name>`                                                                                                                                                                                                     |
| **List Velero Restores**                      | `velero restore get`                                                                                                                                                                                                                     |
| **Set Velero Client Namespace**               | `velero client config set namespace=<namespace>`                                                                                                                                                                                         |
---

## Possible Improvements and Future Additions

### 1. **AWS Backup Lock**
To ensure compliance and protect against accidental or malicious deletion, implementing **AWS Backup Lock** can be an essential addition. AWS Backup Lock enables organizations to enforce immutable backups for a defined period. It prevents modifications or deletion of recovery points, ensuring data integrity.

#### Implementation Steps:
- Use Terraform to configure **backup vault lock** in AWS Backup.
- Define **retention periods** and ensure backups are immutable during the lock duration.

### 2. **AWS Resilience Hub**
Integrating **AWS Resilience Hub** can help assess and improve the reliability and availability of the workloads. It provides comprehensive insights into the resiliency of the architecture and suggests strategies for disaster recovery.

#### Benefits:
- Automate resilience assessments and disaster recovery drills.
- Monitor backup and restore compliance for critical workloads.
- Enhance business continuity planning.

### 3. **Enable Encryption**
To secure sensitive data, use **AWS Key Management Service (KMS)** for encrypting Velero backups in Amazon S3. This ensures the highest level of security for stored data.

### 4. **Multi-Region Backup**
To further enhance disaster recovery capabilities, replicate backups to another AWS region. This protects against region-specific outages.

### 5. **Monitoring with Prometheus and Grafana**
Introduce **Prometheus** and **Grafana** for real-time monitoring of Velero backup jobs and restore processes. This will enable proactive monitoring and alerting for backup-related issues.

### 6. **Backup Optimization with Filters**
Implement more granular backup filtering using Velero's label selectors. This helps back up only the most critical resources, reducing costs and complexity.

### 7. **Data Compression**
Optimize storage costs by compressing backups before storing them in Amazon S3. Tools such as `gzip` can be integrated into the backup process.

### 8. **Disaster Recovery (DR) Playbooks**
Develop DR playbooks and automation scripts for end-to-end recovery in case of catastrophic failures.

---

## Conclusion

This project demonstrated the use of **Velero**, **AWS Backup**, and **Terraform** to create a reliable, automated, and scalable backup and restore solution for Kubernetes workloads. Through this endeavor, we successfully:

1. Integrated Velero with S3 for Kubernetes backups.
2. Automated AWS Backup for critical resources using selection tags.
3. Established recovery strategies for both EKS workloads and S3 data.
4. Addressed real-world challenges such as IAM role configurations, failed backups, and resource conflicts during restore.

The project also provided practical exposure to tools and technologies such as Terraform, AWS CLI, Helm, and Velero, enhancing our understanding of cloud-native backup strategies. Future additions such as **AWS Resilience Hub**, **Backup Lock**, and monitoring enhancements will further strengthen this solution, ensuring robust disaster recovery and business continuity.

With these implementations, this project stands as a comprehensive solution for Kubernetes backup and restore, aligning with industry best practices and real-world scenarios.

---

## Author

Ofri Liberman

- GitHub: https://github.com/libermanofri
- LinkedIn: https://linkedin.com/in/ofriliberman