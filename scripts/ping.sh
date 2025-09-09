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

echo -e "${GREEN}Testing connectivity to ThreeFold Grid Gateway VMs${NC}"
echo "==================================================="

# Check if WireGuard is active (use sudo since wg interface requires root)
if ! sudo wg show gateway >/dev/null 2>&1; then
    echo -e "${RED}ERROR: WireGuard interface 'gateway' not found${NC}"
    echo "Run './scripts/wg.sh' first to set up WireGuard"
    exit 1
fi

echo -e "${YELLOW}WireGuard interface status:${NC}"
sudo wg show gateway
echo ""

# Get VM IPs from Terraform outputs
cd "$INFRASTRUCTURE_DIR"

GATEWAY_WG_IP=$(tofu output -json gateway_wireguard_ip 2>/dev/null | jq -r . 2>/dev/null || echo "")
INTERNAL_WG_IPS=$(tofu output -json internal_wireguard_ips 2>/dev/null || echo "{}")

if [[ -z "$GATEWAY_WG_IP" || "$GATEWAY_WG_IP" == "null" ]]; then
    echo -e "${RED}ERROR: Could not get gateway IP from Terraform outputs${NC}"
    echo "Have you deployed the infrastructure yet?"
    exit 1
fi

echo -e "${YELLOW}Testing connectivity...${NC}"

# Test gateway connectivity
echo -n "Gateway VM ($GATEWAY_WG_IP): "
if ping -c 3 -W 2 "$GATEWAY_WG_IP" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Reachable${NC}"
else
    echo -e "${RED}✗ Unreachable${NC}"
fi

# Test internal VMs
echo "$INTERNAL_WG_IPS" | jq -r 'to_entries[] | "\(.key) \(.value)"' 2>/dev/null | while read -r name ip; do
    if [[ -n "$ip" && "$ip" != "null" ]]; then
        echo -n "Internal VM $name ($ip): "
        if ping -c 3 -W 2 "$ip" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ Reachable${NC}"
        else
            echo -e "${RED}✗ Unreachable${NC}"
        fi
    fi
done

echo ""
echo -e "${YELLOW}Testing SSH connectivity...${NC}"

# Test SSH to gateway
echo -n "SSH to Gateway: "
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@"$GATEWAY_WG_IP" "echo 'SSH OK'" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ SSH OK${NC}"
else
    echo -e "${RED}✗ SSH Failed${NC}"
fi

# Test Mycelium connectivity if available
echo ""
echo -e "${YELLOW}Testing Mycelium connectivity...${NC}"
if command -v mycelium >/dev/null 2>&1; then
    if sudo mycelium inspect --json >/dev/null 2>&1; then
        MYCELIUM_IP=$(sudo mycelium inspect --json | jq -r .address 2>/dev/null || echo "")
        if [[ -n "$MYCELIUM_IP" && "$MYCELIUM_IP" != "null" ]]; then
            echo -e "${GREEN}✓ Mycelium active: $MYCELIUM_IP${NC}"
        else
            echo -e "${YELLOW}⚠ Mycelium running but no IP assigned${NC}"
        fi
    else
        echo -e "${RED}✗ Mycelium command failed${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Mycelium not available locally${NC}"
fi

echo ""
echo -e "${GREEN}Connectivity test completed${NC}"