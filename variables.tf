variable "resource_group_name" {
  description = "Name of the platform resource group."
  type        = string
}

variable "location" {
  type = string
}

variable "environment" {
  type = string
}

variable "project_name" {
  type = string
}

variable "storage_account_name" {
  description = "Name of the ADF data storage account."
  type        = string
}