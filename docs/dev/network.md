# ThreeFold Grid Gateway - Network Architecture & Implementation

## Overview

This document outlines the network architecture and implementation plan for supporting multiple network types (WireGuard and Mycelium) in the tfgrid-gateway project. The goal is to provide users with flexible network connectivity options for both Ansible management and website hosting.

## Current Architecture

### Gateway VM (Public IPv4)
- Hosts main website/status page on public IPv4
- Runs reverse proxy (Nginx/HAProxy) for internal VM routing
- Uses NAT/port forwarding to route public traffic to internal VMs

### Internal VMs
- Run individual websites on specific ports (8081, 8082, etc.)
- Currently accessible via:
  - Direct WireGuard: `http://10.1.4.2:8081`
  - Through Gateway NAT: `http://GATEWAY_PUBLIC_IP:8081`

### Network Setup
1. **WireGuard**: Private IPv4 network (10.1.0.0/16) for secure connectivity
2. **Mycelium**: End-to-end encrypted IPv6 overlay network
3. **Public IPv4**: Gateway's public internet-facing address

## Enhanced Network Architecture

### Network Mode Options

The system supports three network modes:

#### 1. `wireguard-only` (Default)
- **Ansible Access**: Via WireGuard VPN
- **Website Hosting**: Internal VMs bind to WireGuard IPs only
- **Reverse Proxy**: Routes to WireGuard backends
- **NAT Forwarding**: Forwards to WireGuard IPs

#### 2. `mycelium-only`
- **Ansible Access**: Via Mycelium IPv6
- **Website Hosting**: Internal VMs bind to Mycelium IPv6 addresses only
- **Reverse Proxy**: Routes to Mycelium backends
- **NAT Forwarding**: Forwards to Mycelium IPs

#### 3. `both`
- **Ansible Access**: Via preferred network (configurable)
- **Website Hosting**: Internal VMs bind to both networks on same ports
- **Reverse Proxy**: Routes to both network backends
- **NAT Forwarding**: Supports both network types

### Configuration Variables

```bash
# Network mode selection
export NETWORK_MODE=both  # Options: wireguard-only, mycelium-only, both

# Ansible connectivity preference (existing)
export MAIN_NETWORK=wireguard  # Options: wireguard, mycelium
```

## Implementation Details

### Phase 1: Configuration Framework

#### 1.1 Environment Variables
- Add `NETWORK_MODE` support to inventory generation
- Update Makefile to pass network configuration
- Create network-aware Ansible variables

#### 1.2 Inventory Generation Updates
```bash
# scripts/generate_inventory.sh
# Add network mode detection and configuration
NETWORK_MODE="${NETWORK_MODE:-wireguard-only}"
```

### Phase 2: Internal VM Updates

#### 2.1 Website Binding Configuration
Update `platform/roles/vm_demo/templates/nginx.conf.j2`:

```jinja2
server {
    # WireGuard binding (always included)
    listen {{ wireguard_ip }}:{{ vm_port }};

    # Mycelium binding (conditional)
    {% if network_mode in ['mycelium-only', 'both'] %}
    listen [{{ mycelium_ip }}]:{{ vm_port }};
    {% endif %}

    # IPv6 dual-stack support
    {% if network_mode == 'both' %}
    listen [::]:{{ vm_port }};
    {% endif %}
}
```

#### 2.2 Service Configuration
- Update systemd services to bind to appropriate networks
- Add network-specific health checks
- Configure firewall rules for both networks

### Phase 3: Gateway Updates

#### 3.1 Reverse Proxy Updates
Update `platform/roles/gateway_proxy/templates/nginx-gateway.conf.j2`:

```jinja2
upstream backend_http {
{% for host in groups['internal'] %}
    # WireGuard backend
    server {{ hostvars[host]['wireguard_ip'] }}:80;

    {% if network_mode in ['mycelium-only', 'both'] %}
    # Mycelium backend
    server [{{ hostvars[host]['mycelium_ip'] }}]:80;
    {% endif %}
{% endfor %}
}
```

#### 3.2 NAT/Port Forwarding Updates
Update `platform/roles/gateway_nat/tasks/main.yml`:

```bash
# Dynamic port forwarding based on network mode
{% if network_mode in ['wireguard-only', 'both'] %}
nft add rule inet gateway_nat prerouting tcp dport 8081 dnat ip to {{ wireguard_ip }}:8081
{% endif %}

{% if network_mode in ['mycelium-only', 'both'] %}
nft add rule inet gateway_nat prerouting tcp dport 8081 dnat ip to {{ mycelium_ip }}:8081
{% endif %}
```

#### 3.3 Firewall Configuration
```bash
# Allow traffic on both networks
nft add rule inet firewall input ip saddr 10.1.0.0/16 tcp dport 8081 accept   # WireGuard
nft add rule inet firewall input ip6 saddr {{ mycelium_range }} tcp dport 8081 accept  # Mycelium
```

### Phase 4: Testing & Validation

#### 4.1 Connectivity Testing
- Test each network mode independently
- Verify dual network binding works correctly
- Test failover scenarios

#### 4.2 Performance Validation
- Measure latency on both networks
- Test concurrent connections
- Validate load balancing

## Usage Examples

### WireGuard Only (Current Behavior)
```bash
export NETWORK_MODE=wireguard-only
export MAIN_NETWORK=wireguard
make all

# Access: http://GATEWAY_IP:8081 → 10.1.4.2:8081
```

### Mycelium Only
```bash
export NETWORK_MODE=mycelium-only
export MAIN_NETWORK=mycelium
make all

# Access: http://GATEWAY_IP:8081 → [MYCELIUM_IPv6]:8081
```

### Both Networks
```bash
export NETWORK_MODE=both
export MAIN_NETWORK=wireguard  # Ansible via WireGuard
make all

# Access via both networks:
# http://10.1.4.2:8081 (WireGuard)
# http://[MYCELIUM_IPv6]:8081 (Mycelium)
# http://GATEWAY_IP:8081 (via reverse proxy)
```

## Benefits

### Network Redundancy
- Automatic failover if one network fails
- Client can choose optimal network path
- Improved reliability for production deployments

### Flexibility
- Users can choose their preferred network setup
- Easy migration between network types
- Future-proof for additional networks

### Industry Standards
- Follows IPv4/IPv6 dual-stack best practices
- Uses standard ports across networks
- Maintains backward compatibility

## Implementation Checklist

- [ ] Add NETWORK_MODE environment variable support
- [ ] Update inventory generation for network modes
- [ ] Modify vm_demo role for dual network binding
- [ ] Update gateway_proxy for network-aware routing
- [ ] Update gateway_nat for dynamic port forwarding
- [ ] Add comprehensive testing
- [ ] Update documentation

## Troubleshooting

### Network Connectivity Issues
- Verify network mode configuration
- Check firewall rules for both networks
- Test direct connectivity to VM IPs
- Validate reverse proxy upstream configuration

### Performance Issues
- Monitor latency on both networks
- Check for network congestion
- Verify load balancing configuration
- Test with different client locations

## Future Enhancements

### Additional Network Types
- Support for additional overlay networks
- Integration with other VPN technologies
- Dynamic network selection based on performance

### Advanced Features
- Network-specific health monitoring
- Automatic network failover
- Geographic load balancing
- Quality of Service (QoS) configuration