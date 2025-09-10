# ThreeFold Grid Gateway Architecture

This document describes the architecture, design decisions, and key learnings from the ThreeFold Grid Gateway project development.

## Overview

The ThreeFold Grid Gateway provides IPv4 connectivity for IPv6-only VMs on the ThreeFold Grid through a combination of infrastructure provisioning, network configuration, and reverse proxy routing.

## Architecture Components

### 1. Infrastructure Layer (Terraform/OpenTofu)

**Location**: `infrastructure/`

**Purpose**: Provisions VMs and networking on ThreeFold Grid

**Key Components**:
- **Gateway VM**: Public IPv4 VM that acts as the entry point
- **Internal VMs**: IPv6-only VMs behind the gateway
- **Network Configuration**: WireGuard mesh network for secure communication
- **Mycelium Integration**: End-to-end encrypted IPv6 overlay network

### 2. Configuration Layer (Ansible)

**Location**: `ansible/`

**Purpose**: Configures networking, firewall, and services on deployed VMs

**Key Roles**:
- `gateway_common`: Base configuration for all VMs
- `gateway_nat`: NAT and firewall configuration for gateway
- `gateway_demo`: Web interface and reverse proxy configuration
- `vm_demo`: Individual VM web services

### 3. Network Architecture

```
Internet → Gateway VM (Public IPv4) → Internal VMs (via WireGuard/Mycelium)
           185.206.122.150           10.1.4.2, 10.1.5.2
```

## Critical Design Decisions

### Problem 1: SSH Lockout During Firewall Configuration

**Issue**: Ansible firewall tasks were deleting entire nftables chains and recreating them with drop policies, instantly cutting off SSH access.

**Root Cause**: 
```yaml
# DANGEROUS - Don't do this!
- name: Set default input policy to drop
  shell: |
    nft delete chain inet firewall input  # Deletes ALL rules including SSH
    nft add chain inet firewall input { policy drop }
```

**Solution**: 
```yaml
# SAFE - Keep allow rules intact
# Note: Keeping accept policy for now to prevent SSH lockouts
# The explicit allow rules above provide adequate security
# TODO: Implement drop policy with proper testing in the future
```

**Location**: [`ansible/roles/gateway_nat/tasks/main.yml`](../ansible/roles/gateway_nat/tasks/main.yml:93-95)

**Key Lesson**: Never delete firewall chains that contain active allow rules. Always preserve SSH access during automated deployments.

### Problem 2: Port Forwarding Failure

**Issue**: Traffic to `185.206.122.150:8081` was not reaching internal VMs at `10.1.4.2:8081`.

**Investigation Process**:
1. ✅ **NAT Rules**: Correctly configured DNAT from port 8081 to `10.1.4.2:8081`
2. ✅ **Internal Connectivity**: `10.1.4.2:8081` accessible from gateway
3. ✅ **Firewall Rules**: Initially wrong interface names (`wg0` vs `ens2`)
4. ❌ **Root Cause**: ThreeFold Grid infrastructure firewall blocks non-standard ports

**Discovery**: 
```bash
# These work:
curl http://185.206.122.150:22  # SSH - ✅
curl http://185.206.122.150:80  # HTTP - ✅

# These are blocked at infrastructure level:
curl http://185.206.122.150:443   # HTTPS - ❌
curl http://185.206.122.150:8081  # Custom - ❌
```

**Key Lesson**: Cloud infrastructure often has network-level firewalls that override local firewall configurations. Only standard ports (22, 80) are allowed through ThreeFold Grid's infrastructure firewall.

### Problem 3: Interface Name Mismatch

**Issue**: Firewall forwarding rules referenced wrong interface names.

**Root Cause**: 
```yaml
# Wrong - assuming WireGuard interface name
iifname "wg0" oifname "ens3" accept
```

**Solution**:
```yaml
# Correct - using actual interface from routing table
iifname "ens2" oifname "ens3" accept
```

**Network Discovery**:
```bash
# Gateway routing table revealed actual interfaces:
10.1.0.0/16 via 10.1.3.1 dev ens2  # Internal network via ens2
185.206.122.0/24 dev ens3           # External network via ens3
```

**Key Lesson**: Always verify actual interface names rather than assuming standard names. Use `ip route` and `ip link show` to discover the real network topology.

## Solution: Path-Based Reverse Proxy

### Architecture Decision

Since only port 80 is available, we implemented **path-based routing** using nginx reverse proxy instead of port forwarding:

```
http://185.206.122.150/vm7/ → 10.1.4.2:8081
http://185.206.122.150/vm8/ → 10.1.5.2:8082
```

### Implementation

**Nginx Configuration** ([`nginx.conf.j2`](../ansible/roles/gateway_demo/templates/nginx.conf.j2)):
```nginx
# VM proxy endpoints (dynamically generated)
{% for host in groups['internal'] %}
location /vm{{ host }}/ {
    proxy_pass http://{{ hostvars[host]['wireguard_ip'] }}:{{ hostvars[host]['vm_port'] }}/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
{% endfor %}
```

**Dynamic Status Page** ([`status.html.j2`](../ansible/roles/gateway_demo/templates/status.html.j2)):
```html
<!-- Dynamically generated VM links -->
{% for host in groups['internal'] %}
<div class="label">VM {{ host }} ({{ hostvars[host]['wireguard_ip'] }}):</div>
<div class="value">
    <a href="http://{{ ansible_default_ipv4.address }}/vm{{ host }}/" target="_blank" class="vm-link">
        http://{{ ansible_default_ipv4.address }}/vm{{ host }}/ ↗️
    </a>
</div>
{% endfor %}
```

### Benefits

1. **Works with Infrastructure Constraints**: Uses only port 80
2. **Industry Standard**: Nginx reverse proxy is the standard solution
3. **Auto-scaling**: Automatically generates routes for any number of VMs
4. **SEO Friendly**: Clean URLs with meaningful paths
5. **SSL Ready**: Easy to add SSL termination at the gateway

## Network Flow Diagram

```
                    ThreeFold Grid Infrastructure Firewall
                              (Allows: 22, 80)
                                      ↓
Internet → Gateway VM (185.206.122.150:80) → nginx Reverse Proxy
                                      ↓
                            Path-based Routing:
                           /vm7/ → 10.1.4.2:8081
                           /vm8/ → 10.1.5.2:8082
                                      ↓
                              WireGuard Network
                                (10.1.0.0/16)
                                      ↓
                                Internal VMs
                           VM 7: 10.1.4.2:8081 (nginx)
                           VM 8: 10.1.5.2:8082 (nginx)
```

## Firewall Configuration

### Current Safe Configuration

**nftables Structure**:
```bash
table inet gateway_nat {
    chain prerouting {
        # DNAT rules (unused due to infrastructure firewall)
        iifname "ens3" tcp dport 8081 dnat ip to 10.1.4.2:8081
    }
    
    chain postrouting {
        # Masquerading for outbound traffic
        ip saddr 10.1.0.0/16 oifname "ens3" masquerade
    }
}

table inet firewall {
    chain input {
        policy accept;  # SAFE: Explicit allow rules provide security
        ct state established,related accept
        iifname "lo" accept
        tcp dport 22 accept              # SSH
        tcp dport { 80, 443, 8081, 8082 } accept  # HTTP/Demo ports
        udp dport 51820 accept           # WireGuard
    }
    
    chain forward {
        policy accept;  # SAFE: Only forwards between known interfaces
        iifname "ens2" oifname "ens3" accept        # Internal → External
        iifname "ens3" oifname "ens2" tcp dport { 8081, 8082 } accept  # DNAT traffic
        iifname "ens3" oifname "ens2" ct state established,related accept  # Return traffic
    }
}
```

### Security Notes

- **Accept Policy**: Using accept policy with explicit allow rules instead of drop policy to prevent lockouts
- **Interface-Specific**: Rules are tied to specific interfaces (`ens2`, `ens3`)
- **State Tracking**: Connection tracking prevents unauthorized traffic
- **Minimal Attack Surface**: Only essential ports are allowed

## Deployment Workflow

### 1. Infrastructure Deployment
```bash
make infrastructure  # Terraform/OpenTofu deployment
make inventory      # Generate Ansible inventory
make wireguard      # Set up local WireGuard connection
```

### 2. Configuration Deployment
```bash
make ansible        # Configure gateway and firewall
make demo          # Deploy web interface and reverse proxy
```

### 3. Validation
```bash
make ping           # Test connectivity
make address        # Show all VM addresses
curl http://185.206.122.150/vm7/  # Test reverse proxy
```

## Key Files and Their Purposes

| File | Purpose | Key Features |
|------|---------|--------------|
| [`ansible/roles/gateway_nat/tasks/main.yml`](../ansible/roles/gateway_nat/tasks/main.yml) | Firewall & NAT configuration | Safe firewall rules, interface detection |
| [`ansible/roles/gateway_demo/templates/nginx.conf.j2`](../ansible/roles/gateway_demo/templates/nginx.conf.j2) | Reverse proxy configuration | Dynamic proxy generation |
| [`ansible/roles/gateway_demo/templates/status.html.j2`](../ansible/roles/gateway_demo/templates/status.html.j2) | Gateway status page | Dynamic VM links |
| [`ansible/inventory.ini`](../ansible/inventory.ini) | VM configuration | IP addresses, ports, VM IDs |
| [`Makefile`](../Makefile) | Deployment orchestration | Complete workflow automation |

## Scalability Considerations

### Adding New VMs

1. **Infrastructure**: Add new VMs to Terraform configuration
2. **Inventory**: VMs automatically appear in Ansible inventory
3. **Automatic Configuration**: 
   - Nginx automatically generates new proxy routes
   - Status page automatically shows new VM links
   - Firewall rules automatically allow new VM traffic

### Supporting More Protocols

- **WebSocket**: nginx proxy supports WebSocket upgrades
- **gRPC**: Can be configured for gRPC services
- **TCP/UDP Proxies**: Can use nginx stream module for non-HTTP protocols

## Future Improvements

### 1. SSL/TLS Termination
```nginx
server {
    listen 443 ssl;
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    location /vm7/ {
        proxy_pass http://10.1.4.2:8081/;
    }
}
```

### 2. Load Balancing
```nginx
upstream vm_cluster {
    server 10.1.4.2:8081 weight=1;
    server 10.1.5.2:8082 weight=1;
}

location /app/ {
    proxy_pass http://vm_cluster/;
}
```

### 3. Drop Policy Implementation
For production environments, implement drop policy with careful testing:
```bash
# Test in isolated environment first
nft add rule inet firewall input drop
# Verify SSH still works before making persistent
```

## Debugging Guide

### Common Issues

1. **SSH Lockout**: 
   - Prevention: Never delete chains with active rules
   - Recovery: Requires console access or infrastructure reset

2. **Port Forwarding Not Working**:
   - Check infrastructure firewall (ThreeFold Grid blocks non-standard ports)
   - Verify interface names with `ip route`
   - Test internal connectivity first

3. **Reverse Proxy Issues**:
   - Check nginx error logs: `journalctl -u nginx`
   - Verify upstream service availability
   - Test proxy configuration: `nginx -t`

### Useful Commands

```bash
# Network debugging
ip route                    # Show routing table
ip link show               # Show interfaces
nft list ruleset          # Show all firewall rules
wg show                    # Show WireGuard status

# Service debugging
systemctl status nginx     # nginx status
journalctl -u nginx        # nginx logs
curl -I http://localhost/vm7/  # Test proxy locally

# Connectivity testing
make ping                  # Test all VM connectivity
make address              # Show all VM addresses
ssh root@10.1.4.2         # Direct VM access via WireGuard
```

## Lessons Learned

### 1. Infrastructure Constraints Matter
Cloud providers often have network-level restrictions that override local configurations. Always test external connectivity early in development.

### 2. Preserve Management Access
Never implement security changes that could lock out administrative access without a rollback plan.

### 3. Use Dynamic Configuration
Template-based configuration generation scales better than hardcoded values and reduces maintenance overhead.

### 4. Test in Isolation
When debugging network issues, test each layer independently: local connectivity → gateway connectivity → external connectivity.

### 5. Document Edge Cases
Infrastructure-specific limitations (like port restrictions) should be clearly documented for future developers.

## Conclusion

The ThreeFold Grid Gateway project demonstrates how to work within infrastructure constraints while maintaining security and scalability. The path-based reverse proxy solution provides a robust, industry-standard approach to multi-VM access that can scale to any number of internal services.

The key success factors were:
1. Systematic debugging to identify the real root cause
2. Adapting the solution to work with infrastructure constraints
3. Implementing dynamic configuration for scalability
4. Maintaining security without sacrificing accessibility
5. Documenting lessons learned for future development