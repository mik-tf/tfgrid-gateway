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
	@echo "Demo and Testing:"
	@echo "  make demo            - Deploy gateway with live demo status page"
	@echo "  make vm-demo         - Deploy individual VM demo websites"
	@echo "  make full-demo       - Complete deployment with gateway + VM demos + port forwarding"
	@echo "  make demo-status     - Check demo status and connectivity"
	@echo "  make demo-test       - Run comprehensive gateway tests"
	@echo "  make quick-demo      - Complete deployment with demo (infra + config + demo)"
	@echo ""
	@echo "Quick deployment:"
	@echo "  make                 - Deploy everything (infrastructure + inventory + ansible)"
	@echo "  make quick-demo      - Deploy with live demo status page"
	@echo ""
	@echo "Gateway types (set GATEWAY_TYPE environment variable):"
	@echo "  export GATEWAY_TYPE=gateway_nat     - NAT-based gateway (default)"
	@echo "  export GATEWAY_TYPE=gateway_proxy   - Proxy-based gateway"
	@echo ""
	@echo "Demo Features:"
	@echo "  - Live status page at http://GATEWAY_IP"
	@echo "  - JSON API at http://GATEWAY_IP/api/status"
	@echo "  - Health check at http://GATEWAY_IP/health"
	@echo "  - Real-time gateway information and capabilities"
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
	@GATEWAY_IP=$$(cd infrastructure && tofu output -json gateway_public_ip 2>/dev/null | jq -r . 2>/dev/null | sed 's|/.*||' || echo ""); \
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
	@cd ansible && ansible-playbook -i inventory.ini --extra-vars "gateway_type=${GATEWAY_TYPE:-gateway_nat} configure_internal_vms=false" site.yml

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

# Demo commands
demo:
	@echo "Deploying gateway with demo status page..."
	@cd ansible && ansible-playbook -i inventory.ini --extra-vars "gateway_type=${GATEWAY_TYPE:-gateway_nat} enable_demo=true" site.yml

demo-status:
	@echo "Checking gateway demo status..."
	@GATEWAY_IP=$$(cd infrastructure && tofu output -json gateway_public_ip 2>/dev/null | jq -r . 2>/dev/null | sed 's|/.*||' || echo ""); \
	if [[ -z "$$GATEWAY_IP" || "$$GATEWAY_IP" == "null" ]]; then \
		echo "Gateway IP not found. Have you deployed infrastructure yet?"; \
		echo "Run 'make infrastructure' first."; \
		exit 1; \
	fi; \
	echo "Gateway Demo Status:"; \
	echo "==================="; \
	echo "URL: http://$$GATEWAY_IP"; \
	echo "API: http://$$GATEWAY_IP/api/status"; \
	echo "Health: http://$$GATEWAY_IP/health"; \
	echo ""; \
	echo "Testing connectivity..."; \
	curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://$$GATEWAY_IP/health || echo "Connection failed"

demo-test:
	@echo "Running comprehensive gateway tests..."
	@./scripts/test-gateway.sh

# Advanced demo commands
vm-demo:
	@echo "Deploying VM-specific demo websites..."
	@cd ansible && ansible-playbook -i inventory.ini --extra-vars "gateway_type=${GATEWAY_TYPE:-gateway_nat} enable_vm_demo=true" site.yml

full-demo: infrastructure inventory demo vm-demo demo-status
	@echo "Full demo deployment completed!"
	@echo "Gateway Status: http://$$(cd infrastructure && tofu output -json gateway_public_ip 2>/dev/null | jq -r . 2>/dev/null | sed 's|/.*||')"
	@echo "VM 1 (port 8081): http://$$(cd infrastructure && tofu output -json gateway_public_ip 2>/dev/null | jq -r . 2>/dev/null | sed 's|/.*||'):8081"
	@echo "VM 2 (port 8082): http://$$(cd infrastructure && tofu output -json gateway_public_ip 2>/dev/null | jq -r . 2>/dev/null | sed 's|/.*||'):8082"

# Quick deployment with demo
quick-demo: infrastructure inventory demo demo-status