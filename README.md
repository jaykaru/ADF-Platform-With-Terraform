# ADF Platform With Terraform

This project manages an Azure Data Factory (ADF) platform with Terraform. The platform configuration defines a resource group, data storage, a Data Factory, a user-assigned managed identity, a Key Vault, role assignments and a managed private endpoint. Review the plan before applying to see which resources will be created or changed.

## 📌 Progress and next steps

- [x] Created the `sc-adf-dev` service connection; its service principal was shown with **Contributor** on the subscription.
- [x] Confirmed **Storage Blob Data Contributor** for the service principal in the state storage account's IAM.
- [ ] Confirm the bootstrap apply completed successfully and check that the `tfstate` container exists.
- [ ] Back up `bootstrap/terraform.tfstate` privately.
- [ ] Confirm the pipeline values match the bootstrap outputs; configure the `adf-platform-dev` approval and authorize the pipeline.
- [ ] Run the pipeline manually on `main`, review its plan, approve the apply and verify `rg-adfdemo-dev` and `dev.tfstate`.

The role assignment was confirmed in the portal; the bootstrap apply outcome and pipeline deployment have not yet been confirmed here.

## 📁 Project structure

```text
main.tf                       # Platform resource group and module calls
variables.tf                  # Platform inputs
outputs.tf                    # Future platform outputs
providers.tf                  # Remote state backend configuration
.terraform.lock.hcl           # Locked platform provider version and checksums
environments/
  dev.tfvars                  # Development platform values; intended for Git
pipelines/
  azure-pipelines.yml         # Azure DevOps Plan and Apply pipeline
modules/
  storage/                    # Platform data storage module
    main.tf
    variables.tf
    outputs.tf
  data-factory/               # Data Factory module
    main.tf
    variables.tf
    outputs.tf
  managed-identity/           # User-assigned managed identity module
    main.tf
    variables.tf
    outputs.tf
bootstrap/                    # Separate configuration for state storage and blob RBAC
  main.tf
  variables.tf
  outputs.tf
  bootstrap.tfvars            # Local identity inputs; ignored by Git
.gitignore
README.md
```

## 🧭 How the two Terraform configurations work

1. **Bootstrap:** creates a resource group, storage account, private blob container, and blob role assignments. Its own state is initially stored locally in `bootstrap/terraform.tfstate`.
2. **ADF platform:** the configuration in the project root uses the blob container for its separate state file, such as `dev.tfstate`. Running it does not update bootstrap state. The root configuration calls the storage, Data Factory and managed identity modules.

The user-assigned managed identity is attached to ADF and has role assignments in the configuration for the data storage account and Key Vault. It is separate from the pipeline service connection. Configuring the identity and permissions does not create an ADF credential or linked service; those need to be configured before ADF can use them to access data.

The managed private endpoint targets the storage account's `dfs` endpoint. Check and approve the connection where required, and configure a managed virtual network integration runtime and linked service separately. The endpoint does not by itself disable public access or make every ADF connection private.

The platform uses `environments/dev.tfvars` for development values instead of a root `terraform.tfvars`. Terraform does not load it automatically: pass `"-var-file=environments/dev.tfvars"` to commands such as `terraform plan`. It selects the name `rg-adfdemo-dev`, the region `francecentral` and the `dev` environment.

The `.gitignore` allows `environments/*.tfvars` to be committed so future pipelines can use them; other `.tfvars` files, including `bootstrap/bootstrap.tfvars`, remain ignored. **Never put secrets in environment variable files**; use an appropriate secrets-management solution instead.

The storage account uses France Central, geo-redundant storage (GRS), TLS 1.2, blob versioning and 30-day blob and container soft-delete retention, matching the existing Azure Enterprise Platform bootstrap. `prevent_destroy` protects the three storage resources while their resource blocks remain in the configuration; it is not a substitute for backups or Azure access controls.

> [!WARNING]
> Terraform state and saved plans can contain sensitive values, including storage account keys. Never commit or share them. Back up `bootstrap/terraform.tfstate` privately after every bootstrap change, and restrict access to the remote state account.

## 🔑 Blob access managed through Terraform

The bootstrap assigns the built-in **Storage Blob Data Contributor** role at the **state storage account** scope, separately for every Microsoft Entra object ID in `state_blob_principal_object_ids`. This gives access to blobs in all containers in this account, not to all storage accounts in the subscription. Use this account only for appropriately trusted state files.

- Use the **object ID** of the user, group or service principal—not an application/client ID.
- Add your own user if you will access the backend from your laptop. Add the pipeline service principal separately when it exists.
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

For a service connection, find its service principal's **Object ID** in Microsoft Entra ID > Enterprise applications > the service principal > Overview. The service connection ID, application/client ID and App registration object ID are different; do not use them for this role assignment. Alternatively, sign in to the correct tenant and look up the object ID using the application/client ID:

```bash
az ad sp show --id "<application-client-id>" --query id --output tsv
```

In `bootstrap/bootstrap.tfvars`, supply the service principal object ID. Create this local file if it does not exist; keep any existing entries when adding identities:

```hcl
state_blob_principal_object_ids = {
  pipeline = "SERVICE-PRINCIPAL-OBJECT-ID"
  # Add local_user = "YOUR-USER-OBJECT-ID" if your user needs blob access.
}
```

The storage account name defaults to `stadftfstatefrc001`; override it in the same file if needed. Names must be globally unique, 3–24 lowercase letters and numbers. Azure determines whether the name is available. The input file is ignored by Git; preserve a private copy so you can manage the same assignments later.

The defaults are `francecentral`, `rg-adf-tfstate-frc-001`, and container `tfstate`; override these in the same file if needed. Do not reuse the existing Enterprise Platform state account name.

### 3. Initialize, validate, plan and apply

In PowerShell, from the project root (not from within `bootstrap`):

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

### 🔎 Verify bootstrap and role access

- Check the bootstrap apply output completed successfully; from `bootstrap`, run `terraform output backend_config` and compare it with the pipeline values.
- In Azure portal, open **Storage accounts > `stadftfstatefrc001` > Containers** and check for `tfstate`.
- Open **Storage account > Access control (IAM) > Role assignments** and confirm the ADF service principal has **Storage Blob Data Contributor**. This blob role is separate from the subscription-level **Contributor** role.
- Store a private backup of the local bootstrap state. The platform's `dev.tfstate` is separate and is written by a later platform apply.

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

The platform configuration defines a resource group, storage, Data Factory, managed identity, Key Vault, role assignments and a managed private endpoint. Backend initialization alone does not deploy anything or create the state file. If you already have platform state elsewhere, stop and follow Terraform's [state migration guidance](https://developer.hashicorp.com/terraform/language/settings/backends/configuration#migrate-state-between-backends) instead of starting with an empty backend.

After initializing the backend, select the development values explicitly from the project root:

```powershell
terraform plan "-var-file=environments/dev.tfvars" "-out=dev.tfplan"
```

Review the plan before applying it. The environment file chooses variable values; the `key=dev.tfstate` backend setting above separately chooses the state file.

## 🔄 Azure DevOps pipeline

The pipeline in `pipelines/azure-pipelines.yml` installs Terraform 1.13.3 and runs **Plan**, publishes the saved plan, then runs **Apply** on `main` using that exact plan. It uses a workload identity federation service connection and Microsoft Entra blob authentication. Automatic triggers are disabled (`trigger: none`); run it manually once setup is complete.

> [!IMPORTANT]
> Verify the pipeline values and complete the steps below before running it. An Azure DevOps environment name alone does **not** create an approval: configure the approval check before the first run.

1. **Create and authorize the service connection.** In Azure DevOps, go to **Project settings > Service connections** and create an Azure Resource Manager service connection using workload identity federation for the intended subscription. Confirm `serviceConnection` in the YAML matches its exact name. Permit this pipeline to use it when requested.
2. **Check the subscription and permissions.** Confirm `subscriptionId` is the ID of the subscription selected in the service connection. The pipeline checks that they match. The service connection identity needs permissions to manage the platform resources **and** `Microsoft.Authorization/roleAssignments/write` at the data storage account and Key Vault scopes, to grant roles to the ADF identity. Contributor alone cannot create role assignments. Use appropriately scoped permissions approved by your administrator; unrestricted subscription-wide access is broader than necessary.
3. **Create state storage and give blob access.** Complete the bootstrap setup above. Add the pipeline service principal's **object ID** to `state_blob_principal_object_ids` in `bootstrap/bootstrap.tfvars`, then review and apply the bootstrap plan. If bootstrap was already applied, apply a new bootstrap plan with the added identity. Do not remove your existing identities. This creates **Storage Blob Data Contributor** at the state storage account scope; Contributor alone does not grant blob data access. Wait for role propagation.
4. **Check the backend values.** Use `terraform output backend_config` from the bootstrap directory to verify `stateResourceGroup`, `stateStorageAccount` and `stateContainer` in the pipeline. The environment name `dev` selects `environments/dev.tfvars` and the `dev.tfstate` blob.
5. **Create the approval.** In Azure DevOps, open **Pipelines > Environments**, create `adf-platform-dev`, then open its **Approvals and checks** and add the appropriate approver. Restrict access to the environment and service connection. Without this check Apply will not wait for a human approval.
6. **Create the pipeline.** Commit and push the files, including `.terraform.lock.hcl`. In Azure DevOps choose **Pipelines > New pipeline**, connect the repository, and select **Existing Azure Pipelines YAML file** with path `pipelines/azure-pipelines.yml`. Authorize required resources and manually run it on `main` once the values and prerequisites are confirmed.
7. **Review before approving.** Check the planned resource group, data storage, Data Factory, managed identity, Key Vault, role assignments and private endpoint against the current configuration and state. If an existing Data Factory changes identity type, review the impact on existing connections and permissions before approving. If the plan proposes anything unexpected, reject it and investigate. After approval, Apply runs the saved plan; verify the deployed resources and the `dev.tfstate` blob in Azure.

The saved plan can contain sensitive data. Limit access to the pipeline and its artifacts and use an appropriate retention period. The pipeline does not run bootstrap or assign its own roles.

### 📌 Pipeline improvements to revisit later

- [ ] After the first successful manual run, consider automatic triggers for changes to the platform and pipeline files.
- [ ] Add clearer checks and troubleshooting messages for missing or incorrect pipeline configuration.
- [ ] Restore Terraform download verification, preferably including verification of HashiCorp's signed checksums.
- [ ] Consider sharing repeated install and authentication steps through templates if more pipelines are added.
- [ ] Review artifact access, retention, approval rules and least-privilege permissions as the project grows.

## 🔎 Troubleshooting

| Symptom | Why | What to check |
|---|---|---|
| `AuthorizationFailed` creating a role assignment | The bootstrap identity lacks role-assignment write permission at the scope, or is subject to a restriction | Subscription or resource group > Access control (IAM); ask an administrator for the required access |
| `AuthorizationPermissionMismatch` or 403 during backend initialization | The signed-in identity lacks blob data access, or the assignment has not propagated | Storage account > Access control (IAM); confirm the correct **object ID** and wait before retrying |
| Storage account name already taken | Storage account names are globally unique | Choose another name in `bootstrap.tfvars` |
| `Too many command line arguments` in PowerShell | An argument was split | Quote arguments containing a dot, as in the commands above |
| Terraform wants to recreate existing bootstrap resources | Bootstrap local state is missing, or the wrong subscription is selected | Stop; restore the private state backup or follow [Terraform import guidance](https://developer.hashicorp.com/terraform/language/import) after checking the subscription |

### 🛠️ Issues encountered during bootstrap setup

| What you see | Why it happens | What to do / where to look |
|---|---|---|
| Terraform prompts for backend `container_name` during bootstrap setup | `terraform init` was likely run in the project root, which configures the platform's remote backend, rather than in `bootstrap` | Cancel with Ctrl+C. From the project root, enter `bootstrap` and rerun `terraform init`. The bootstrap variable `state_container_name` defaults to `tfstate`; backend settings are separate. |
| `AADSTS7000222` says a client secret has expired | Old `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET` and `ARM_TENANT_ID` environment credentials can make Terraform use an old service principal instead of the Azure CLI login | Clear the stale credentials from the current shell, sign in with `az login`, select the subscription and retry. Remove saved User-scope credentials only if no other project needs them. Never print or share secret values. |
| Several different IDs appear for the service connection | Azure DevOps service connection ID, app/client ID, App registration object ID and service principal object ID identify different things | Use the **service principal object ID** from Enterprise applications or `az ad sp show` in `bootstrap.tfvars`. |
| Contributor is visible but Terraform cannot access blobs | Contributor is a management role; it does not by itself grant Microsoft Entra blob data access | Check **Storage Blob Data Contributor** for the correct identity on the state storage account. Allow time for role propagation. |

## 📚 References

- [AzureRM role assignment](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment)
- [Azure Storage backend and Microsoft Entra authentication](https://developer.hashicorp.com/terraform/language/backend/azurerm)
- [Assign Azure roles using the Azure portal: prerequisites](https://learn.microsoft.com/azure/role-based-access-control/role-assignments-portal#prerequisites)
