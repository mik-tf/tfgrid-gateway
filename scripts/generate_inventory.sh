#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR="$SCRIPT_DIR/.."
INFRASTRUCTURE_DIR="$PROJECT_DIR/infrastructure"
PLATFORM_DIR="$PROJECT_DIR/platform"

# Load configuration from .env file if it exists
if [[ -f "$PROJECT_DIR/.env" ]]; then
    source "$PROJECT_DIR/.env"
fi

# Use variables with fallbacks
MAIN_NETWORK="${MAIN_NETWORK:-wireguard}"
NETWORK_MODE="${NETWORK_MODE:-wireguard-only}"
GATEWAY_TYPE="${GATEWAY_TYPE:-gateway_nat}"

echo -e "${GREEN}Generating Ansible inventory from Terraform outputs${NC}"
if [[ -f "$PROJECT_DIR/.env" ]]; then
    echo -e "${YELLOW}Loading configuration from .env file${NC}"
fi
echo -e "${YELLOW}Using MAIN_NETWORK: ${MAIN_NETWORK}${NC}"
echo -e "${YELLOW}Using NETWORK_MODE: ${NETWORK_MODE}${NC}"
echo -e "${YELLOW}Using GATEWAY_TYPE: ${GATEWAY_TYPE}${NC}"

# Check if Terraform state exists
if [[ ! -f "$INFRASTRUCTURE_DIR/terraform.tfstate" ]]; then
    echo -e "${RED}ERROR: Terraform state not found. Run infrastructure deployment first.${NC}"
    exit 1
fi

cd "$INFRASTRUCTURE_DIR"

# Get Terraform outputs
echo -e "${YELLOW}Fetching Terraform outputs...${NC}"

GATEWAY_PUBLIC_IP=$(tofu output -json gateway_public_ip 2>/dev/null | jq -r . 2>/dev/null | sed 's|/.*||' || echo "")
GATEWAY_WIREGUARD_IP=$(tofu output -json gateway_wireguard_ip 2>/dev/null | jq -r . 2>/dev/null | sed 's|/.*||' || echo "")
GATEWAY_MYCELIUM_IP=$(tofu output -json gateway_mycelium_ip 2>/dev/null | jq -r . 2>/dev/null || echo "")

INTERNAL_WIREGUARD_IPS=$(tofu output -json internal_wireguard_ips 2>/dev/null || echo "{}")
INTERNAL_MYCELIUM_IPS=$(tofu output -json internal_mycelium_ips 2>/dev/null || echo "{}")

# Generate inventory file
INVENTORY_FILE="$PLATFORM_DIR/inventory.ini"

cat > "$INVENTORY_FILE" << EOF
[all:vars]
ansible_user=root
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'

[gateway]
gateway ansible_host=${GATEWAY_PUBLIC_IP}

[gateway:vars]
wireguard_ip=${GATEWAY_WIREGUARD_IP}
mycelium_ip=${GATEWAY_MYCELIUM_IP}
internal_ip=${GATEWAY_WIREGUARD_IP}

[internal]
EOF

# Add internal VMs with port assignments
if [[ "$MAIN_NETWORK" == "mycelium" ]]; then
    # Use mycelium IPs for ansible_host with sequential ports
    echo "$INTERNAL_WIREGUARD_IPS" | jq -r 'to_entries | sort_by(.key | tonumber) | to_entries[] | "\(.value.key) ansible_host=\(.value.value) wireguard_ip=\(.value.value) vm_port=\(8001 + .key) vm_id=\(.value.key)"' >> "$INVENTORY_FILE"
else
    # Use wireguard IPs for ansible_host (default)
    echo "$INTERNAL_WIREGUARD_IPS" | jq -r 'to_entries | sort_by(.key | tonumber) | to_entries[] | "\(.value.key) ansible_host=\(.value.value) wireguard_ip=\(.value.value) vm_port=\(8001 + .key) vm_id=\(.value.key)"' >> "$INVENTORY_FILE"
fi

# Add internal variables
cat >> "$INVENTORY_FILE" << EOF

[internal:vars]
EOF

echo "$INTERNAL_MYCELIUM_IPS" | jq -r 'to_entries[] | "internal_\(.key)_mycelium_ip=\(.value)"' >> "$INVENTORY_FILE"

# Create group variables
mkdir -p "$PLATFORM_DIR/group_vars"

# Gateway group variables
cat > "$PLATFORM_DIR/group_vars/gateway.yml" << EOF
---
# Gateway configuration
gateway_type: "{{ lookup('env', 'GATEWAY_TYPE') | default('gateway_nat', true) }}"

# Network configuration
network_mode: "$NETWORK_MODE"

# Port forwarding (for NAT gateway)
port_forwards: []

# Proxy configuration (for proxy gateway)
proxy_ports: [8080, 8443]
udp_ports: []
enable_ssl: false
domain_name: ""
ssl_email: ""

# Testing
enable_testing: false
EOF

# Internal group variables
cat > "$PLATFORM_DIR/group_vars/internal.yml" << EOF
---
# Internal VM configuration
services:
  - name: web
    port: 80
    type: http
  - name: api
    port: 8080
    type: tcp
EOF

# All group variables
cat > "$PLATFORM_DIR/group_vars/all.yml" << EOF
---
# Global configuration
ansible_python_interpreter: /usr/bin/python3

# Network configuration
network_cidr: "10.1.0.0/16"
wireguard_port: 51820
network_mode: "{{ lookup('env', 'NETWORK_MODE') | default('wireguard-only', true) }}"
disable_port_forwarding: "{{ lookup('env', 'DISABLE_PORT_FORWARDING') | default('false', true) | lower }}"
gateway_type: "{{ lookup('env', 'GATEWAY_TYPE') | default('gateway_nat', true) }}"

# Mycelium configuration
mycelium_enabled: true
EOF

echo -e "${GREEN}Inventory generated successfully!${NC}"
echo "Inventory file: $INVENTORY_FILE"
echo "Main network (Ansible): $MAIN_NETWORK"
echo "Network mode (Website): $NETWORK_MODE"
echo ""
echo -e "${YELLOW}Available gateway types:${NC}"
echo "  - gateway_nat: NAT-based gateway with nftables"
echo "  - gateway_proxy: Proxy-based gateway with HAProxy/Nginx"
echo ""
echo -e "${YELLOW}Available network types (Ansible connectivity):${NC}"
echo "  - wireguard: Use WireGuard VPN for Ansible connectivity (default)"
echo "  - mycelium: Use Mycelium IPv6 overlay for Ansible connectivity"
echo ""
echo -e "${YELLOW}Available network modes (Website hosting):${NC}"
echo "  - wireguard-only: Websites on WireGuard only (default)"
echo "  - mycelium-only: Websites on Mycelium only"
echo "  - both: Websites on both networks (redundancy)"
echo ""
echo -e "${YELLOW}To use a specific gateway type:${NC}"
echo "  export GATEWAY_TYPE=gateway_proxy"
echo "  ansible-playbook -i platform/inventory.ini platform/site.yml"
echo ""
echo -e "${YELLOW}To configure network settings:${NC}"
echo "  export MAIN_NETWORK=mycelium"
echo "  export NETWORK_MODE=both"
echo "  make inventory"