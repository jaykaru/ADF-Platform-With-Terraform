mock_provider "azurerm" {
  mock_resource "azurerm_storage_account" {
    override_during = plan

    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/stadftfstatetest001"
    }
  }
}

variables {
  state_storage_account_name = "stadftfstatetest001"
  state_blob_principal_object_ids = {
    local_user = "11111111-1111-1111-1111-111111111111"
    pipeline   = "22222222-2222-2222-2222-222222222222"
  }
}

run "assign_blob_role_at_storage_account_scope" {
  command = plan

  assert {
    condition     = length(azurerm_role_assignment.state_blob_contributor) == 2
    error_message = "There must be one blob role assignment per configured identity."
  }

  assert {
    condition = alltrue([
      for assignment in azurerm_role_assignment.state_blob_contributor :
      assignment.scope == azurerm_storage_account.state.id &&
      assignment.role_definition_name == "Storage Blob Data Contributor"
    ])
    error_message = "Each identity must receive Storage Blob Data Contributor on the state storage account."
  }

  assert {
    condition     = azurerm_role_assignment.state_blob_contributor["pipeline"].principal_id == var.state_blob_principal_object_ids["pipeline"]
    error_message = "The role assignment must use the specified principal object ID."
  }
}

run "reject_empty_principals" {
  command = plan

  variables {
    state_blob_principal_object_ids = {}
  }

  expect_failures = [var.state_blob_principal_object_ids]
}

run "reject_duplicate_principals" {
  command = plan

  variables {
    state_blob_principal_object_ids = {
      first  = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
      second = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    }
  }

  expect_failures = [var.state_blob_principal_object_ids]
}

run "reject_invalid_storage_name" {
  command = plan

  variables {
    state_storage_account_name = "Not Valid!"
  }

  expect_failures = [var.state_storage_account_name]
}
