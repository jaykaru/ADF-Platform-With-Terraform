# ADF Platform With Terraform

This project will manage an Azure Data Factory (ADF) platform with Terraform. It currently contains the **state bootstrap**, backend configuration and platform/module placeholders; it does not yet create a data factory.

## 📁 Project structure

```text
main.tf                       # Future platform resources and module calls
variables.tf                  # Future platform inputs
outputs.tf                    # Future platform outputs
providers.tf                  # Remote state backend configuration
environments/
  dev.tfvars                  # Development platform values; intended for Git
modules/
  storage/                    # Future platform storage module
    main.tf
    variables.tf
    outputs.tf
  data-factory/               # Future Data Factory module
    main.tf
    variables.tf
    outputs.tf
bootstrap/                    # Separate configuration for state storage and blob RBAC
  main.tf
  variables.tf
  outputs.tf
  bootstrap.tfvars.example    # Template; copy to bootstrap.tfvars
  tests/
.gitignore
README.md
```

## 🧭 How the two Terraform configurations work

1. **Bootstrap:** creates a resource group, storage account, private blob container, and blob role assignments. Its own state is initially stored locally in `bootstrap/terraform.tfstate`.
2. **ADF platform:** the future configuration in the project root uses the blob container for its separate state file, such as `dev.tfstate`. Running it does not update bootstrap state. The storage and Data Factory module files are placeholders, not yet connected to the root configuration.

The platform uses `environments/dev.tfvars` for development values instead of a root `terraform.tfvars`. Terraform does not load it automatically: pass `"-var-file=environments/dev.tfvars"` to commands such as `terraform plan`. This file is currently a placeholder because the platform has no declared variables yet.

The `.gitignore` allows `environments/*.tfvars` to be committed so future pipelines can use them; other `.tfvars` files, including `bootstrap/bootstrap.tfvars`, remain ignored. **Never put secrets in environment variable files**; use an appropriate secrets-management solution instead.

The storage account uses France Central, geo-redundant storage (GRS), TLS 1.2, blob versioning and 30-day blob and container soft-delete retention, matching the existing Azure Enterprise Platform bootstrap. `prevent_destroy` protects the three storage resources while their resource blocks remain in the configuration; it is not a substitute for backups or Azure access controls.

> [!WARNING]
> Terraform state and saved plans can contain sensitive values, including storage account keys. Never commit or share them. Back up `bootstrap/terraform.tfstate` privately after every bootstrap change, and restrict access to the remote state account.

## 🔑 Blob access managed through Terraform

The bootstrap assigns the built-in **Storage Blob Data Contributor** role at the **state storage account** scope, separately for every Microsoft Entra object ID in `state_blob_principal_object_ids`. This gives access to blobs in all containers in this account, not to all storage accounts in the subscription. Use this account only for appropriately trusted state files.

- Use the **object ID** of the user, group or service principal—not an application/client ID.
- Add your own user if you will access the backend from your laptop. Add the pipeline service principal separately when it exists. Pipeline setup is not included yet.
- Keep each map label stable. Removing an entry and applying removes that Terraform-managed role assignment; changing a label can replace it. The apply identity must retain permission to manage role assignments.
- This role is for **blob data**. The future pipeline or user also needs appropriate Azure management permissions to create ADF resources; this bootstrap does not grant those permissions.
- Role assignments are not necessarily immediate: allow time for Azure RBAC propagation before testing access.

Infrastructure as code makes access changes reviewable and repeatable, but it does not grant itself permissions. The identity running bootstrap needs permission to create the storage resources **and** `Microsoft.Authorization/roleAssignments/write` at the storage account scope (for example, an appropriately scoped Owner, or Contributor plus Role Based Access Control Administrator, subject to any restrictions). Deleting assignments later also needs `Microsoft.Authorization/roleAssignments/delete`. Contributor alone cannot manage role assignments.

The backend instructions below use Microsoft Entra authentication rather than account keys. As in the original bootstrap, the storage account's shared-key access is not disabled; it is not restricted to Entra-only access by this configuration.

## 🚀 One-time bootstrap setup

### 1. Select the Azure subscription

Install [Terraform](https://developer.hashicorp.com/terraform/install) 1.13.x and the [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli). Sign in with an identity that has the permissions described above:

```powershell
az login
az account set --subscription "<subscription-id>"
az account show --query "{name:name,id:id,tenantId:tenantId}" --output table
```

Check for stale `ARM_*` environment variables if Terraform uses an unexpected identity. Terraform provider environment credentials can take precedence over your Azure CLI session; do not print or share secret values.

### 2. Choose the identities and storage account name

For your signed-in user, obtain the object ID:

```powershell
az ad signed-in-user show --query id --output tsv
```

For a service connection, find its service principal's **Object ID** in Microsoft Entra ID > Enterprise applications > the service principal > Overview. The service connection's application/client ID is different. Ask an administrator if you cannot see the identity.

From the project root:

```powershell
Copy-Item .\bootstrap\bootstrap.tfvars.example .\bootstrap\bootstrap.tfvars
```

Edit `bootstrap\bootstrap.tfvars`: choose a globally unique storage account name (3–24 lowercase letters and numbers), replace the example object ID, and add entries for any other authorized identities. Azure determines whether the account name is available. The file is ignored by Git; preserve a private copy of these inputs so you can manage the same assignments later.

The defaults are `francecentral`, `rg-adf-tfstate-frc-001`, and container `tfstate`; override these in the same file if needed. Do not reuse the existing Enterprise Platform state account name.

### 3. Initialize, validate, plan and apply

In PowerShell, from the project root:

```powershell
Set-Location .\bootstrap
terraform init
terraform validate
terraform plan "-var-file=bootstrap.tfvars" "-out=bootstrap.tfplan"
```

Read the plan carefully: it should create the resource group, storage account, container and one role assignment per configured identity. Check the subscription and role-assignment scope before proceeding. When satisfied, apply the exact saved plan:

```powershell
terraform apply "bootstrap.tfplan"
terraform output backend_config
```

Keep the bootstrap state backed up privately. The saved plan is ignored by Git and should be handled as sensitive data too. Run future bootstrap changes from this folder, with the same input file, and review the plan first.

## 💾 Configure remote state for the ADF platform

After bootstrap succeeds and RBAC has propagated, use the three values from `terraform output backend_config` below. From the project root:

```powershell
terraform init `
  "-backend-config=resource_group_name=<resource-group-name>" `
  "-backend-config=storage_account_name=<storage-account-name>" `
  "-backend-config=container_name=<container-name>" `
  "-backend-config=key=dev.tfstate" `
  "-backend-config=use_azuread_auth=true"
```

The signed-in user must have the blob data role too; assigning it only to a pipeline does not give your user access. If the role was just assigned, wait and retry after propagation. Use a distinct state key for each environment and choose access boundaries deliberately—separate keys alone are not security isolation.

The platform and module files are currently placeholders. Add and review the ADF resources and module calls before planning or applying; backend initialization alone does not deploy ADF or create its state file. If you already have platform state elsewhere, stop and follow Terraform's [state migration guidance](https://developer.hashicorp.com/terraform/language/settings/backends/configuration#migrate-state-between-backends) instead of starting with an empty backend.

When platform variables and resources have been added and the backend has been initialized, select the development values explicitly from the project root:

```powershell
terraform plan "-var-file=environments/dev.tfvars" "-out=dev.tfplan"
```

Review the plan before applying it. The environment file chooses variable values; the `key=dev.tfstate` backend setting above separately chooses the state file.

## 🔎 Troubleshooting

| Symptom | Why | What to check |
|---|---|---|
| `AuthorizationFailed` creating a role assignment | The bootstrap identity lacks role-assignment write permission at the scope, or is subject to a restriction | Subscription or resource group > Access control (IAM); ask an administrator for the required access |
| `AuthorizationPermissionMismatch` or 403 during backend initialization | The signed-in identity lacks blob data access, or the assignment has not propagated | Storage account > Access control (IAM); confirm the correct **object ID** and wait before retrying |
| Storage account name already taken | Storage account names are globally unique | Choose another name in `bootstrap.tfvars` |
| `Too many command line arguments` in PowerShell | An argument was split | Quote arguments containing a dot, as in the commands above |
| Terraform wants to recreate existing bootstrap resources | Bootstrap local state is missing, or the wrong subscription is selected | Stop; restore the private state backup or follow [Terraform import guidance](https://developer.hashicorp.com/terraform/language/import) after checking the subscription |

## 📚 References

- [AzureRM role assignment](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment)
- [Azure Storage backend and Microsoft Entra authentication](https://developer.hashicorp.com/terraform/language/backend/azurerm)
- [Assign Azure roles using the Azure portal: prerequisites](https://learn.microsoft.com/azure/role-based-access-control/role-assignments-portal#prerequisites)
