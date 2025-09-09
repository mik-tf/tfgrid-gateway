# ThreeFold Grid Gateway Deployment Guide

This document explains how the tfgrid-gateway deployment works with multiple nodes, using the example of 1 gateway node and 2 internal nodes.

## Architecture Overview

### Current Setup: 1 Gateway + 2 Internal Nodes

```
┌─────────────────┐     ┌─────────────────┐
│   Gateway VM    │     │  Internal VM 1  │
│  (Public IPv4)  │◄───►│  (IPv6-only)    │
│                 │     │  Services:      │
│ • NAT/Proxy     │     │  • Web Server   │
│ • WireGuard     │     │  • API Server   │
│ • Mycelium      │     │                 │
│ • Firewall      │     └─────────────────┘
└─────────────────┘             ▲
          ▲                     │
          │                     │
          ▼                     ▼
┌─────────────────┐     ┌─────────────────┐
│  Internal VM 2  │     │   Internet      │
│  (IPv6-only)    │     │   (IPv4)        │
│  Services:      │     │                 │
│  • Database     │     └─────────────────┘
│  • Cache        │             ▲
└─────────────────┘             │
          ▲                     │
          └─────────────────────┘
               Traffic Flow
```

## How It Works

### 1. Infrastructure Layer (Terraform/OpenTofu)

The `infrastructure/main.tf` creates:

- **1 Gateway VM**: With public IPv4 address for internet connectivity
- **2 Internal VMs**: IPv6-only VMs without public IPv4 addresses
- **Network**: Private WireGuard network (10.1.0.0/16) connecting all VMs
- **Mycelium**: End-to-end encrypted IPv6 overlay network for all VMs

**Key Configuration:**
```hcl
# Gateway node with public IPv4
resource "grid_deployment" "gateway" {
  node         = var.gateway_node
  network_name = grid_network.gateway_network.name
  vms {
    publicip = true  # This gets the public IPv4
    # ... other config
  }
}

# Internal nodes without public IPv4
resource "grid_deployment" "internal_vms" {
  for_each = toset([for n in var.internal_nodes : tostring(n)])
  vms {
    publicip = false  # No public IPv4
    # ... other config
  }
}
```

### 2. Network Layer

**WireGuard VPN Network:**
- All VMs connect via encrypted WireGuard tunnels
- Gateway VM: `10.1.0.1` (WireGuard IP)
- Internal VM 1: `10.1.0.10` (WireGuard IP)
- Internal VM 2: `10.1.0.11` (WireGuard IP)

**Mycelium IPv6 Network:**
- Each VM gets a unique cryptographic IPv6 address
- Example: `400::1:2:3:4:5:6` (Mycelium IP)
- End-to-end encrypted communication between all VMs

### 3. Gateway Functionality

The gateway VM provides two main functions:

#### NAT Gateway (`gateway_nat`)
- **IP Masquerading**: Internal VMs can access internet through gateway's public IPv4
- **Port Forwarding**: External traffic can reach internal services
- **Firewall**: nftables rules control traffic flow

#### Proxy Gateway (`gateway_proxy`)
- **Load Balancing**: Distribute traffic across multiple internal VMs
- **SSL Termination**: Handle HTTPS certificates
- **Application Routing**: Route based on URL paths or domains

## Traffic Flow Examples

### Example 1: Web Service Access

```
Internet User → Gateway Public IPv4:80 → Internal VM 1:80
                                      → Internal VM 2:80 (load balancing)
```

1. User accesses `http://gateway-public-ip/`
2. Gateway receives traffic on port 80
3. Gateway forwards to internal VMs based on configuration:
   - NAT: Port forwarding rules
   - Proxy: Load balancing across available backends

### Example 2: Internal VM Communication

```
Internal VM 1 → Internal VM 2
```

1. VMs communicate via WireGuard (10.1.0.10 ↔ 10.1.0.11)
2. Or via Mycelium IPv6 addresses
3. Gateway is not involved in internal traffic

### Example 3: Outbound Internet Access

```
Internal VM 1 → Internet
```

1. Internal VM sends traffic to gateway (10.1.0.1)
2. Gateway performs NAT masquerading
3. Traffic appears to come from gateway's public IPv4
4. Internet services respond to gateway's public IP

## Scalability: Adding More Internal Nodes

### How to Add More Nodes

**Option 1: Modify Configuration**
```hcl
# In infrastructure/credentials.auto.tfvars
internal_nodes = [2000, 2001, 2002, 2003]  # Add more node IDs
```

**Option 2: Dynamic Scaling**
The Terraform configuration automatically handles any number of internal nodes:

```hcl
resource "grid_deployment" "internal_vms" {
  for_each = toset([for n in var.internal_nodes : tostring(n)])
  # Each node gets its own VM with unique IPs
}
```

### Scaling Considerations

**✅ What Scales Automatically:**
- Network configuration (WireGuard IPs assigned automatically)
- Mycelium keys and addresses (generated per node)
- Ansible inventory (generated from Terraform outputs)
- Load balancing (proxy gateway distributes across all nodes)

**⚠️ What Needs Manual Configuration:**
- Port forwarding rules (NAT gateway)
- Load balancer backends (proxy gateway)
- Service discovery (if using dynamic services)

### Example: Scaling to 5 Internal Nodes

```
Configuration:
internal_nodes = [2000, 2001, 2002, 2003, 2004]

Result:
- Gateway VM: 1 (public IPv4)
- Internal VMs: 5 (IPv6-only)
- Total VMs: 6
- Network: 10.1.0.0/16 (supports up to 65,534 devices)
```

### Load Balancing with Multiple Nodes

**NAT Gateway:**
- Configure multiple port forwarding rules
- Round-robin DNS or external load balancer
- Manual traffic distribution

**Proxy Gateway:**
- Automatic load balancing across all internal nodes
- Health checks for service availability
- Session persistence if needed

## Configuration Examples

### Basic Setup (1 Gateway + 2 Internal)
```bash
# Configure node IDs
gateway_node = 1000
internal_nodes = [2000, 2001]

# Deploy
make infrastructure
make inventory
make ansible
```

### Scaled Setup (1 Gateway + 5 Internal)
```bash
# Configure more nodes
internal_nodes = [2000, 2001, 2002, 2003, 2004]

# Deploy (same commands work)
make infrastructure
make inventory
make ansible
```

### High Availability (Multiple Gateways)
```bash
# Future enhancement: multiple gateway nodes
gateway_nodes = [1000, 1001]  # Active-passive or load balanced
internal_nodes = [2000, 2001, 2002]
```

## Network Address Assignment

### Automatic IP Assignment
- **WireGuard**: Sequential IPs in 10.1.0.0/16 range
- **Mycelium**: Cryptographic IPv6 addresses (deterministic per node)
- **Public IPv4**: Assigned by ThreeFold Grid to gateway VM

### IP Ranges Used
- **WireGuard Network**: 10.1.0.0/16
  - Gateway: 10.1.0.1
  - Internal VMs: 10.1.0.10, 10.1.0.11, 10.1.0.12, etc.
- **Mycelium Network**: 400::/7 (assigned by Mycelium)
- **Public IPv4**: Assigned by ThreeFold Grid

## Monitoring and Troubleshooting

### Check Current Configuration
```bash
# View all IPs
tofu -chdir=infrastructure output

# Test connectivity
make ping

# Run tests
make ansible-test
```

### Common Scaling Issues
1. **IP Address Exhaustion**: Use larger subnet if needed
2. **Performance**: Monitor gateway VM resources
3. **Load Balancing**: Ensure proper distribution across nodes
4. **Network Latency**: Mycelium optimizes routes automatically

## Summary

The current setup with 1 gateway + 2 internal nodes is fully scalable:

- **Add more internal nodes** by updating `internal_nodes` list
- **Same deployment commands** work regardless of node count
- **Automatic configuration** generation for any number of nodes
- **Load balancing** works out of the box with proxy gateway
- **Network addresses** assigned automatically

The architecture supports from 1 internal node to hundreds of internal nodes, limited only by:
- Available ThreeFold Grid capacity
- Gateway VM performance
- Network design requirements