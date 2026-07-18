terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

variable "location" {
  type    = string
  default = "centralus"
}

variable "project" {
  type    = string
  default = "cloudlink"
}

variable "alert_email" {
  description = "Email address to notify when the DLQ depth or downstream failure-rate alert fires"
  type        = string
}

variable "dlq_alert_threshold" {
  description = "Number of messages in orders-dlq that triggers the alert"
  type        = number
  default     = 5
}

resource "azurerm_resource_group" "this" {
  name     = "${var.project}-rg"
  location = var.location
}

# --- Messaging: Service Bus namespace + main queue + dead-letter queue ---

resource "azurerm_servicebus_namespace" "this" {
  name                = "${var.project}-sb-${random_string.suffix.result}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Standard"
}

resource "azurerm_servicebus_queue" "orders" {
  name         = "orders"
  namespace_id = azurerm_servicebus_namespace.this.id

  max_delivery_count                   = 5
  default_message_ttl                  = "P1D"
  dead_lettering_on_message_expiration = true
}

# Explicit DLQ-style queue for failures routed by the Logic App (in addition to
# the queue's built-in system DLQ, this one is app-routed so it's independently
# alertable and inspectable without needing DLQ-specific tooling).
resource "azurerm_servicebus_queue" "orders_dlq" {
  name         = "orders-dlq"
  namespace_id = azurerm_servicebus_namespace.this.id

  default_message_ttl = "P7D"
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# --- Logic App ---
# Workflow definition is maintained in ../logic-app/workflow.json and loaded here
# so the app logic isn't duplicated in Terraform HCL.

resource "azurerm_logic_app_workflow" "order_intake" {
  name                = "${var.project}-order-intake"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  workflow_schema  = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
  workflow_version = "1.0.0.0"
}

# NOTE: azurerm_logic_app_workflow manages triggers/actions via separate
# azurerm_logic_app_trigger_* / azurerm_logic_app_action_* resources, OR via
# az CLI / ARM deployment of logic-app/workflow.json directly. For a workflow
# this size, deploying the JSON via `az logic workflow create` or an ARM
# template wrapper is more maintainable than re-encoding every action in HCL.
# See infra/deploy-workflow.sh.

# --- Monitor alert: DLQ depth ---

resource "azurerm_monitor_action_group" "integration_oncall" {
  name                = "${var.project}-oncall"
  resource_group_name = azurerm_resource_group.this.name
  short_name          = "cloudlink"

  email_receiver {
    name          = "oncall-email"
    email_address = var.alert_email
  }
}

resource "azurerm_monitor_metric_alert" "dlq_depth" {
  name                = "${var.project}-dlq-depth-alert"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_servicebus_namespace.this.id]
  description         = "Fires when orders-dlq message count exceeds threshold — see docs/runbook-dlq-alert.md"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.ServiceBus/namespaces"
    metric_name      = "Messages"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.dlq_alert_threshold

    dimension {
      name     = "EntityName"
      operator = "Include"
      values   = ["orders-dlq"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.integration_oncall.id
  }
}

# --- Downstream fulfillment API (App Service) ---

resource "azurerm_service_plan" "downstream_api" {
  name                = "${var.project}-downstream-plan"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  os_type             = "Linux"
  sku_name            = "F1" # Free tier — fine for a low-traffic demo
}

data "azurerm_client_config" "current" {}

resource "azurerm_api_connection" "servicebus" {
  name                = "${var.project}-servicebus-connection"
  resource_group_name = azurerm_resource_group.this.name
  managed_api_id      = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${var.location}/managedApis/servicebus"

  parameter_values = {
    connectionString = azurerm_servicebus_namespace.this.default_primary_connection_string
  }

  lifecycle {
    ignore_changes = [parameter_values]
  }
}

resource "azurerm_linux_web_app" "downstream_api" {
  name                = "${var.project}-downstream-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  service_plan_id     = azurerm_service_plan.downstream_api.id

  site_config {
    always_on = false
    application_stack {
      python_version = "3.12"
    }
    app_command_line = "uvicorn main:app --host 0.0.0.0 --port 8000"
  }

  app_settings = {
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    SIMULATE_FAILURE_RATE          = "0.0"
  }
}

output "downstream_api_url" {
  value = "https://${azurerm_linux_web_app.downstream_api.default_hostname}/fulfillment"
}


# --- API Management (TODO: throttling policy) ---
# Scaffolded but intentionally left as a TODO — see README "Status" section.
# resource "azurerm_api_management" "this" { ... }

output "resource_group" {
  value = azurerm_resource_group.this.name
}

output "service_bus_namespace" {
  value = azurerm_servicebus_namespace.this.name
}

output "logic_app_name" {
  value = azurerm_logic_app_workflow.order_intake.name
}
