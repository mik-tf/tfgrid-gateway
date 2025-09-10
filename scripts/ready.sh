#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR="$SCRIPT_DIR/.."
INFRASTRUCTURE_DIR="$PROJECT_DIR/infrastructure"

echo -e "${BLUE}ThreeFold Grid Gateway VM Readiness Check${NC}"
echo "=========================================="

# Check if Terraform outputs exist
cd "$INFRASTRUCTURE_DIR"

GATEWAY_IP=$(tofu output -json gateway_public_ip 2>/dev/null | jq -r . 2>/dev/null | sed 's|/.*||' || echo "")
if [[ -z "$GATEWAY_IP" || "$GATEWAY_IP" == "null" ]]; then
    echo -e "${RED}ERROR: Gateway public IP not found in Terraform outputs${NC}"
    echo "Have you deployed infrastructure yet?"
    echo "Run 'make infrastructure' first."
    exit 1
fi

echo -e "${YELLOW}Gateway Public IP: $GATEWAY_IP${NC}"
echo ""

echo -e "${BLUE}Checking gateway connectivity...${NC}"

# Simple ping test to gateway public IP
if ping -c 3 -W 5 "$GATEWAY_IP" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Gateway is reachable via ping${NC}"
    echo ""
    echo -e "${GREEN}🎉 VMs are ready!${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "  make wireguard    # Set up WireGuard connectivity"
    echo "  make ansible      # Configure gateway with Ansible"
    exit 0
else
    echo -e "${RED}✗ Gateway is not reachable${NC}"
    echo "This might indicate:"
    echo "  - VMs are still booting"
    echo "  - Network connectivity issues"
    echo "  - ThreeFold Grid deployment problems"
    exit 1
fi