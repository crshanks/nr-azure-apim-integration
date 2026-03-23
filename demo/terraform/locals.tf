locals {
  loc = var.location_abbreviation
  env = var.environment

  backend_container_group_name = var.backend_container_group_name != "" ? var.backend_container_group_name : "aci-mock-backend-${local.env}-${local.loc}"

  # DNS label must be globally unique within the Azure region — used as the FQDN prefix.
  # ACI assigns: <dns_name_label>.<region>.azurecontainer.io
  backend_dns_label = "mock-backend-${local.env}-${local.loc}"
}
