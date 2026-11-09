variable "location" {
  description = "Azure region for the state resources."
  type        = string
  default     = "francecentral"
}

variable "state_resource_group_name" {
  description = "Resource group that holds the Terraform state storage."
  type        = string
  default     = "rg-adf-tfstate-frc-001"
}

variable "state_storage_account_name" {
  description = "Globally unique storage account name (3-24 lowercase letters and numbers)."
  type        = string
  default     = "stadftfstatefrc001"

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.state_storage_account_name))
    error_message = "The storage account name must contain 3-24 lowercase letters and numbers."
  }
}

variable "state_container_name" {
  description = "Blob container that holds the state files."
  type        = string
  default     = "tfstate"
}

variable "state_blob_principal_object_ids" {
  description = "Map of stable labels to Microsoft Entra object IDs that need access to state blobs."
  type        = map(string)

  validation {
    condition = length(var.state_blob_principal_object_ids) > 0 && alltrue([
      for object_id in values(var.state_blob_principal_object_ids) :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", object_id))
    ]) && length(distinct([for object_id in values(var.state_blob_principal_object_ids) : lower(object_id)])) == length(var.state_blob_principal_object_ids)
    error_message = "Provide at least one unique Microsoft Entra object ID in GUID format."
  }
}
