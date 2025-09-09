# ThreeFold Grid IPv4 Gateway

A complete solution for deploying IPv4 gateway VMs on ThreeFold Grid using Terraform/OpenTofu for infrastructure provisioning and automated configuration for secure network connectivity.

## Overview

This repository combines infrastructure provisioning via Terraform/OpenTofu with automated gateway configuration. The entire deployment process is automated through a single command, creating gateway VMs with public IPv4 addresses that enable internet access for IPv6-only workloads through NAT, proxies, WireGuard VPNs, and Mycelium network integration.

### Features

- **Public IPv4 Gateway**: VMs with dedicated public IPv4 addresses for internet connectivity
- **Infrastructure as Code**: Provisions all necessary infrastructure using Terraform/OpenTofu
- **NAT & Proxy Support**: Multiple gateway implementation approaches (NAT, reverse proxies, TCP/UDP proxies)
- **WireGuard Integration**: Secure VPN tunnels between gateway and internal VMs
- **Mycelium Integration**: End-to-end encrypted IPv6 overlay network for all VMs
- **Automated Deployment**: Single command deployment with `make`
- **Flexible Networking**: Support for various network topologies and security configurations
- **Ready for Workloads**: Pre-configured for deploying your applications behind the gateway

## Architecture

The gateway deployment consists of:

1. **Gateway VMs**: Run on ThreeFold Grid with public IPv4 addresses, providing internet access
2. **Internal VMs**: IPv6-only VMs that connect through the gateway for external connectivity
3. **Secure Networks**: WireGuard VPNs and Mycelium overlay networks for encrypted communication

The gateway VMs live within the same network as your internal VMs, providing secure management and connectivity without exposing internal resources to the public internet.

## Prerequisites

- Linux/macOS system with bash
- [OpenTofu](https://opentofu.org/) (or Terraform) installed
- [Ansible](https://www.ansible.com/) installed
- [WireGuard](https://www.wireguard.com/) installed
- [jq](https://stedolan.github.io/jq/) installed
- ThreeFold account with sufficient TFT balance

### Installing Ansible Dependencies

```bash
# Install Ansible collections and roles
cd ansible
ansible-galaxy collection install -r requirements.yml
ansible-galaxy role install -r requirements.yml
```

## 🚀 Quick Start (5 minutes)

**New to tfgrid-gateway?** Follow our [Quick Start Guide](docs/quickstart.md) for a complete step-by-step walkthrough!

### One-Command Deployment
```bash
git clone https://github.com/mik-tf/tfgrid-gateway
cd tfgrid-gateway
cp infrastructure/credentials.auto.tfvars.example infrastructure/credentials.auto.tfvars
nano infrastructure/credentials.auto.tfvars  # Configure your node IDs

# Set your mnemonic (choose one method):
# Option 1: From standard ThreeFold config
export TF_VAR_mnemonic=$(cat ~/.config/threefold/mnemonic)
# Or for Fish shell: set -x TF_VAR_mnemonic (cat ~/.config/threefold/mnemonic)

# Option 2: Manual entry
export TF_VAR_mnemonic="your_mnemonic_here"

make  # Deploy everything automatically!
```

### Access Your Gateway
After deployment, you'll get a public IPv4 address. Access your services at:
- `http://YOUR_IP:8081` → Internal VM 1
- `http://YOUR_IP:8082` → Internal VM 2
- `http://YOUR_IP/web1` → VM 1 (proxy mode)
- `http://YOUR_IP/web2` → VM 2 (proxy mode)

📖 **Detailed Guide**: [docs/quickstart.md](docs/quickstart.md)

### Gateway Types

Choose your gateway configuration by setting the `GATEWAY_TYPE` environment variable:

```bash
# NAT-based gateway (default)
export GATEWAY_TYPE=gateway_nat
make ansible

# Proxy-based gateway with HAProxy and Nginx
export GATEWAY_TYPE=gateway_proxy
make ansible
```

**Available Gateway Types:**
- `gateway_nat`: Traditional NAT gateway using nftables for port forwarding and masquerading
- `gateway_proxy`: Reverse proxy gateway using HAProxy and Nginx for load balancing and SSL termination

## 🎯 Live Demo System

The tfgrid-gateway project includes a comprehensive live demo system that makes it easy to see and test gateway functionality in real-time.

### Quick Demo Deployment

Deploy a fully functional gateway with live status page in one command:

```bash
# Complete demo deployment (infrastructure + configuration + demo)
make quick-demo

# Or step-by-step
make infrastructure  # Deploy VMs and network
make inventory      # Generate Ansible inventory
make demo          # Deploy demo with status page
make demo-status   # Check demo URLs and connectivity
```

### Demo Features

After deployment, you'll have:

- **🌐 Live Status Page**: `http://YOUR_GATEWAY_IP`
  - Real-time gateway configuration
  - Network information and security features
  - System metrics and status
  - Beautiful, responsive web interface

- **📡 JSON API**: `http://YOUR_GATEWAY_IP/api/status`
  - Programmatic access to gateway information
  - Machine-readable status data

- **💓 Health Check**: `http://YOUR_GATEWAY_IP/health`
  - Simple monitoring endpoint
  - Returns "OK" when gateway is healthy

## 🚀 Advanced Multi-VM Demo System

The advanced demo system creates individual websites on each internal VM and configures port forwarding from the gateway, allowing you to access each VM's unique content through different ports.

### Multi-VM Demo Features

- **🖥️ Individual VM Websites**: Each internal VM gets its own nginx website
- **🔀 Port Forwarding**: Gateway forwards different ports to different VMs
- **📊 Dynamic Content**: Each VM shows its specific network information
- **🌐 Unified Access**: Access all VMs through the gateway's public IP

### Example Multi-VM Setup

```
Gateway VM (185.206.122.150)
├── Port 80: Gateway status page
├── Port 8081: VM 1 website (shows VM 1's WireGuard IP, Mycelium IP, etc.)
└── Port 8082: VM 2 website (shows VM 2's WireGuard IP, Mycelium IP, etc.)
```

### Deploying the Advanced Demo

```bash
# Complete multi-VM demo deployment
make full-demo

# This runs:
# 1. Infrastructure deployment (gateway + internal VMs)
# 2. Gateway demo (status page on port 80)
# 3. VM demos (individual websites on internal VMs)
# 4. Port forwarding configuration (ports 8081, 8082, etc.)
```

### Accessing Individual VM Websites

After deployment, access each VM's website:

```bash
# VM 1 website (port 8081)
curl http://YOUR_GATEWAY_IP:8081

# VM 2 website (port 8082)
curl http://YOUR_GATEWAY_IP:8082

# Each VM shows:
# - Its unique VM ID
# - WireGuard IP address
# - Mycelium IP address
# - Gateway connection status
# - System information
```

### Advanced Demo Commands

```bash
# Deploy only VM-specific websites
make vm-demo

# Deploy complete system with port forwarding
make full-demo

# Check all demo URLs and ports
make demo-status

# Run comprehensive tests
make demo-test
```

### What Each VM Website Shows

Each internal VM's website displays:

- **🆔 VM Identity**: Unique VM identifier and hostname
- **🌐 Network Configuration**:
  - WireGuard IP within the private network
  - Mycelium IPv6 address
  - Gateway connection status
- **⚙️ System Information**: CPU, memory, architecture
- **🔗 Gateway Details**: Gateway type, network, connection status
- **📡 API Endpoints**: JSON API for programmatic access

### Perfect For

- **Advanced Learning**: Understand multi-VM networking and port forwarding
- **Real-world Simulation**: Mimic production deployments with multiple services
- **Development Testing**: Test applications across multiple VMs
- **Demonstration**: Show complete ThreeFold Grid gateway capabilities
- **DNS Integration**: Set up `gateway.example.com` pointing to your gateway IP

### What the Demo Shows

The live demo displays:
- **Gateway Type**: NAT, Proxy, or custom configuration
- **Network**: ThreeFold Grid network (main/test/dev)
- **IP Addresses**: Public IPv4, WireGuard IPs, Mycelium IPs
- **Security Features**: Firewall status, VPN connectivity
- **System Information**: Uptime, load, memory, architecture
- **Real-time Status**: Live updates of all gateway capabilities

### Perfect For

- **Learning**: See exactly how ThreeFold Grid gateways work
- **Demonstration**: Show gateway capabilities to others
- **Development**: Use as a foundation for custom projects
- **Testing**: Verify gateway functionality and connectivity
- **Troubleshooting**: Real-time diagnostics and monitoring

4. After deployment, for security, unset the sensitive environment variable:
   ```bash
   unset TF_VAR_mnemonic
   ```

## Deployment Process

The deployment happens in distinct phases, which can be run individually or together:

### 1. Infrastructure Deployment (`make infrastructure`)

Runs `scripts/infrastructure.sh`, which:
- Cleans up any previous infrastructure
- Initializes and applies Terraform/OpenTofu configuration
- Sets up WireGuard connections between VMs
- Generates the Ansible inventory based on deployed nodes
- Tests connectivity to all VMs

### 2. Gateway Configuration (`make configure`)

Runs `scripts/configure.sh`, which:
- Configures NAT rules on gateway VMs
- Sets up proxy services (optional)
- Configures firewall rules
- Enables Mycelium networking
- Tests gateway functionality

## Using the Gateway

After deployment completes, you'll receive the gateway VM's public IPv4 address.

### Connecting to the Gateway VM

```bash
# Connect to the gateway VM
make connect

# Or directly:
ssh root@<gateway-vm-public-ip>
```

### Managing Your Gateway

Once connected to the gateway VM, you can:

```bash
# Check gateway status
sudo nft list ruleset

# View WireGuard connections
sudo wg show

# Check Mycelium connectivity
mycelium inspect --json

# Monitor NAT statistics
sudo nft list table ip nat
```

## Additional Management Commands

```bash
# Check connectivity to all VMs
make ping

# Verify gateway configuration
make verify

# Clean up deployment resources
make clean
```

## Project Structure

```
tfgrid-gateway/
├── infrastructure/    # Infrastructure provisioning (via OpenTofu)
│   ├── credentials.auto.tfvars.example  # Example configuration variables (non-sensitive)
│   └── main.tf        # Main infrastructure definition with secure variable handling
├── scripts/           # Deployment and utility scripts
│   ├── infrastructure.sh # Script to deploy infrastructure
│   ├── configure.sh   # Script to configure gateway
│   ├── cleantf.sh     # Script to clean Terraform/OpenTofu state
│   ├── ping.sh        # Connectivity test utility
│   └── wg.sh          # WireGuard setup script
├── Makefile           # Main interface for all deployment commands
└── docs/              # Additional documentation
    ├── overview.md    # Comprehensive gateway implementation guide
    ├── security.md    # Security best practices documentation
    └── troubleshooting.md # Solutions to common issues
```

## Infrastructure Configuration

In your `credentials.auto.tfvars` file, you can configure:

```
# Gateway node specifications
gateway_cpu = 2
gateway_mem = 4096   # 4GB RAM
gateway_disk = 50    # 50GB storage

# Internal node specifications
internal_cpu = 2
internal_mem = 2048   # 2GB RAM
internal_disk = 25    # 25GB storage

# Node IDs from ThreeFold Grid
gateway_node = 1000   # Gateway node ID
internal_nodes = [2000, 2001]  # Internal node IDs

# Network configuration
network_name = "gateway_network"
ip_range = "10.1.0.0/16"
```

## Maintenance and Updates

### Updating Gateway Configuration

To update your gateway configuration, connect to the gateway VM and run:

```bash
cd ~/tfgrid-gateway/scripts
./configure.sh
```

### Adding or Removing Internal VMs

To add or remove internal VMs:

1. Update your `credentials.auto.tfvars` file
2. Run `make infrastructure` again to update the infrastructure
3. Run `make configure` to reconfigure the gateway

## Troubleshooting

See the [troubleshooting guide](docs/troubleshooting.md) for common issues and solutions.

### Common Issues

#### Gateway Connection Issues

If you can't connect to the gateway VM:

1. Verify the VM has been deployed correctly:
   ```bash
   cd infrastructure
   tofu output gateway_public_ip
   ```

2. Check WireGuard connection status:
   ```bash
   sudo wg show
   ```

#### NAT/Proxy Issues

If internal VMs can't access the internet:

1. Check NAT rules on gateway:
   ```bash
   sudo nft list table inet nat
   ```

2. Verify routing configuration:
   ```bash
   ip route show
   ```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.