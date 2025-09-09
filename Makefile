.PHONY: help infrastructure configure connect ping clean ansible ansible-test inventory

# Default target
all: infrastructure inventory ansible

# Help target
help:
	@echo "ThreeFold Grid Gateway Deployment"
	@echo "================================"
	@echo ""
	@echo "Available targets:"
	@echo "  make infrastructure  - Deploy VMs and network infrastructure"
	@echo "  make inventory       - Generate Ansible inventory from Terraform outputs"
	@echo "  make ansible         - Configure gateway using Ansible"
	@echo "  make ansible-test    - Run gateway tests using Ansible"
	@echo "  make configure       - Configure gateway services (legacy script method)"
	@echo "  make connect         - Connect to gateway VM via SSH"
	@echo "  make ping            - Test connectivity to all VMs"
	@echo "  make clean           - Clean up deployment and remove resources"
	@echo "  make help            - Show this help message"
	@echo ""
	@echo "Quick deployment:"
	@echo "  make                 - Deploy everything (infrastructure + inventory + ansible)"
	@echo ""
	@echo "Gateway types (set GATEWAY_TYPE environment variable):"
	@echo "  export GATEWAY_TYPE=gateway_nat     - NAT-based gateway (default)"
	@echo "  export GATEWAY_TYPE=gateway_proxy   - Proxy-based gateway"
	@echo ""
	@echo "Prerequisites:"
	@echo "  - OpenTofu/Terraform installed"
	@echo "  - Ansible installed"
	@echo "  - ThreeFold account with TFT balance"
	@echo "  - Configure infrastructure/credentials.auto.tfvars"
	@echo "  - Set TF_VAR_mnemonic environment variable"

# Infrastructure deployment
infrastructure:
	@echo "Deploying ThreeFold Grid infrastructure..."
	@./scripts/infrastructure.sh

# Gateway configuration
configure:
	@echo "Configuring gateway services..."
	@echo "Note: This should be run on the gateway VM after infrastructure deployment"
	@echo "SSH to the gateway VM first, then run this command"
	@./scripts/configure.sh

# Connect to gateway
connect:
	@echo "Connecting to gateway VM..."
	@GATEWAY_IP=$$(cd infrastructure && tofu output -json gateway_public_ip 2>/dev/null | jq -r . 2>/dev/null || echo ""); \
	if [[ -z "$$GATEWAY_IP" || "$$GATEWAY_IP" == "null" ]]; then \
		echo "Gateway IP not found. Have you deployed infrastructure yet?"; \
		echo "Run 'make infrastructure' first."; \
		exit 1; \
	fi; \
	echo "Connecting to gateway at $$GATEWAY_IP"; \
	ssh root@$$GATEWAY_IP

# Test connectivity
ping:
	@echo "Testing connectivity to VMs..."
	@./scripts/ping.sh

# Clean up
clean:
	@echo "Cleaning up deployment..."
	@cd infrastructure && tofu destroy -auto-approve 2>/dev/null || true
	@echo "Cleanup completed"

# Generate Ansible inventory
inventory:
	@echo "Generating Ansible inventory..."
	@./scripts/generate_inventory.sh

# Configure with Ansible
ansible:
	@echo "Configuring gateway with Ansible..."
	@cd ansible && ansible-playbook -i inventory.ini --extra-vars "gateway_type=${GATEWAY_TYPE:-gateway_nat}" site.yml

# Test with Ansible
ansible-test:
	@echo "Testing gateway configuration with Ansible..."
	@cd ansible && ansible-playbook -i inventory.ini test-gateway.yml

# WireGuard setup
wireguard:
	@echo "Setting up WireGuard..."
	@./scripts/wg.sh

# Verify deployment
verify:
	@echo "Verifying deployment..."
	@./scripts/verify.sh