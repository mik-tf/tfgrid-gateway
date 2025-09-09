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

echo -e "${GREEN}Verifying ThreeFold Grid Gateway Deployment${NC}"
echo "============================================="

ERRORS=0

# Check Terraform state
echo -e "${YELLOW}Checking Terraform state...${NC}"
cd "$INFRASTRUCTURE_DIR"

if [[ ! -f "terraform.tfstate" ]]; then
    echo -e "${RED}✗ Terraform state file not found${NC}"
    ((ERRORS++))
else
    echo -e "${GREEN}✓ Terraform state exists${NC}"
fi

# Check outputs
echo -e "${YELLOW}Checking Terraform outputs...${NC}"

GATEWAY_IP=$(tofu output -json gateway_public_ip 2>/dev/null | jq -r . 2>/dev/null || echo "")
if [[ -z "$GATEWAY_IP" || "$GATEWAY_IP" == "null" ]]; then
    echo -e "${RED}✗ Gateway public IP not found${NC}"
    ((ERRORS++))
else
    echo -e "${GREEN}✓ Gateway public IP: $GATEWAY_IP${NC}"
fi

# Check WireGuard configuration
echo -e "${YELLOW}Checking WireGuard configuration...${NC}"
if [[ ! -f "/etc/wireguard/gateway.conf" ]]; then
    echo -e "${RED}✗ WireGuard config not found at /etc/wireguard/gateway.conf${NC}"
    echo "  Run './scripts/wg.sh' to set up WireGuard"
    ((ERRORS++))
else
    echo -e "${GREEN}✓ WireGuard config exists${NC}"

    if ! sudo wg show gateway >/dev/null 2>&1; then
        echo -e "${RED}✗ WireGuard interface 'gateway' not active${NC}"
        ((ERRORS++))
    else
        echo -e "${GREEN}✓ WireGuard interface active${NC}"
    fi
fi

# Check gateway connectivity if WireGuard is active
if sudo wg show gateway >/dev/null 2>&1; then
    echo -e "${YELLOW}Testing gateway connectivity...${NC}"

    GATEWAY_WG_IP=$(tofu output -json gateway_wireguard_ip 2>/dev/null | jq -r . 2>/dev/null || echo "")
    if [[ -n "$GATEWAY_WG_IP" && "$GATEWAY_WG_IP" != "null" ]]; then
        if ping -c 2 -W 2 "$GATEWAY_WG_IP" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ Gateway reachable via WireGuard${NC}"
        else
            echo -e "${RED}✗ Gateway not reachable via WireGuard${NC}"
            ((ERRORS++))
        fi
    fi
fi

# Check Mycelium if available
echo -e "${YELLOW}Checking Mycelium status...${NC}"
if command -v mycelium >/dev/null 2>&1; then
    if sudo mycelium inspect --json >/dev/null 2>&1; then
        MYCELIUM_IP=$(sudo mycelium inspect --json | jq -r .address 2>/dev/null || echo "")
        if [[ -n "$MYCELIUM_IP" && "$MYCELIUM_IP" != "null" ]]; then
            echo -e "${GREEN}✓ Mycelium active, IP: $MYCELIUM_IP${NC}"
        else
            echo -e "${YELLOW}⚠ Mycelium running but no IP assigned yet${NC}"
        fi
    else
        echo -e "${RED}✗ Mycelium command failed${NC}"
        ((ERRORS++))
    fi
else
    echo -e "${YELLOW}⚠ Mycelium not installed or not in PATH${NC}"
fi

# Summary
echo ""
if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}✓ All checks passed! Deployment looks good.${NC}"
    exit 0
else
    echo -e "${RED}✗ Found $ERRORS issue(s) that need attention.${NC}"
    exit 1
fi