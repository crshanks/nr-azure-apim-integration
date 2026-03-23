.PHONY: test test-collector test-policy test-terraform test-bicep

## Run all local validation tests (no Azure credentials required)
test: test-collector test-policy test-terraform test-bicep
	@echo ""
	@echo "All tests passed."

## Validate otel-collector-config.yaml using otelcol-contrib Docker image
test-collector:
	@chmod +x tests/collector/validate.sh
	@tests/collector/validate.sh

## Validate apim-policy.xml.tpl structure and AppRequests schema
test-policy:
	@chmod +x tests/policy/validate.sh
	@tests/policy/validate.sh

## Validate Terraform configuration (terraform init + validate)
test-terraform:
	@chmod +x tests/terraform/validate.sh
	@tests/terraform/validate.sh terraform
	@tests/terraform/validate.sh demo/terraform

## Validate Bicep files (bicep build / az bicep build)
test-bicep:
	@chmod +x tests/bicep/validate.sh
	@tests/bicep/validate.sh
