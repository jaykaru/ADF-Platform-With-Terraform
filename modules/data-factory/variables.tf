# Add Data Factory module input variables here.
variable "data_factory_name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "user_assigned_identity_id" {
  description = "Resource ID of the user assigned managed identity"
  type        = string
}

variable "location" {
  type = string
}

variable "tags" {
  type = map(string)
}