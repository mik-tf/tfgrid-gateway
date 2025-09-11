# 🚀 ThreeFold Grid Gateway Quick Start

Get your IPv4 gateway up and running in minutes! This guide shows you how to deploy a gateway VM with internal services accessible from the internet.

## 📋 Prerequisites

- Linux/macOS system
- [OpenTofu](https://opentofu.org/) or [Terraform](https://terraform.io/) installed
- [Ansible](https://ansible.com/) installed
- [WireGuard](https://wireguard.com/) installed
- ThreeFold account with TFT balance
- SSH keys configured

## ⚡ Quick Deployment (5 minutes)

### Step 1: Clone and Setup
```bash
git clone https://github.com/mik-tf/tfgrid-gateway
cd tfgrid-gateway

# Install Ansible dependencies
ansible-galaxy collection install -r platform/requirements.yml
ansible-galaxy role install -r platform/requirements.yml
```

### Step 2: Configure Your Deployment
```bash
# Copy example configuration
cp infrastructure/credentials.auto.tfvars.example infrastructure/credentials.auto.tfvars

# Edit with your node IDs (get from ThreeFold Grid Explorer)
nano infrastructure/credentials.auto.tfvars
```

**Example configuration:**
```hcl
# ThreeFold Grid Network
network = "main"  # Options: main, test, dev

# Your ThreeFold Grid node IDs
gateway_node = 1000    # Node with public IPv4 capability
internal_nodes = [2000, 2001]  # IPv6-only nodes for your services

# VM sizes (adjust as needed)
gateway_cpu = 2
gateway_mem = 4096
internal_cpu = 2
internal_mem = 2048
```

### Step 3: Set Your Mnemonic (Securely)

**Option 1: From ThreeFold Config (Recommended)**
```bash
# If you have your mnemonic stored in the standard location:
# Bash
export TF_VAR_mnemonic=$(cat ~/.config/threefold/mnemonic)

# Fish shell
set -x TF_VAR_mnemonic (cat ~/.config/threefold/mnemonic)
```

**Option 2: Manual Entry (Secure)**
```bash
# NEVER put your mnemonic directly in commands
set +o history
export TF_VAR_mnemonic="your_actual_mnemonic_phrase_here"
set -o history
```

**Option 3: One-liner for Fish shell**
```fish
set -x TF_VAR_mnemonic (cat ~/.config/threefold/mnemonic) && make
```

### Step 4: Deploy Everything
```bash
# One command deployment
make

# This runs:
# 1. Infrastructure deployment (VMs + network)
# 2. Inventory generation (Ansible hosts)
# 3. Gateway configuration (firewall + routing)
```

### Step 5: Get Your Gateway Address
```bash
# After deployment completes, get the public IPv4
tofu -chdir=infrastructure output gateway_public_ip
```

**Example output:**
```
203.0.113.10
```

## 🌐 Access Your Gateway

### Option 1: NAT Gateway (Port Forwarding)
```
http://YOUR_GATEWAY_IP:8081  → Internal VM 1
http://YOUR_GATEWAY_IP:8082  → Internal VM 2
http://YOUR_GATEWAY_IP:3306  → Database on VM 3
```

### Option 2: Proxy Gateway (Path Routing)
```
http://YOUR_GATEWAY_IP/web1   → Internal VM 1 content
http://YOUR_GATEWAY_IP/web2   → Internal VM 2 content
http://YOUR_GATEWAY_IP/api    → API on VM 3
```

### Option 3: Load Balancing
```
http://YOUR_GATEWAY_IP/        → Alternates between all internal VMs
```

## 🔧 Gateway Types

Choose your gateway type by setting an environment variable:

### NAT Gateway (Default)
```bash
export GATEWAY_TYPE=gateway_nat
make ansible
```
- Traditional network address translation
- Port forwarding to internal services
- Best for simple routing scenarios

### Proxy Gateway
```bash
export GATEWAY_TYPE=gateway_proxy
make ansible
```
- Load balancing across multiple VMs
- SSL termination support
- Advanced routing capabilities

## 📊 What You Get

After deployment, you have:

- **1 Gateway VM** with public IPv4 address
- **Multiple Internal VMs** (IPv6-only, cost-effective)
- **Secure Network** (WireGuard VPN between all VMs)
- **Encrypted Overlay** (Mycelium IPv6 for all VMs)
- **Automatic Routing** (Internet ↔ Gateway ↔ Internal VMs)

## 🧪 Testing Your Deployment

```bash
# Test connectivity
make ping

# Run comprehensive tests
make ansible-test

# Check gateway status
tofu -chdir=infrastructure output
```

## 🔄 Scaling Up

Want more internal VMs? Just update the configuration:

```bash
# Add more nodes
nano infrastructure/credentials.auto.tfvars
# internal_nodes = [2000, 2001, 2002, 2003, 2004]

# Redeploy
make infrastructure
make inventory
make ansible
```

The system automatically configures routing for all VMs!

## 🛠️ Manual Steps (Alternative)

If you prefer step-by-step control:

```bash
# 1. Deploy infrastructure
make infrastructure

# 2. Generate Ansible inventory
make inventory

# 3. Configure gateway
make ansible

# 4. Test everything
make ansible-test
```

## 📈 Monitoring & Management

```bash
# SSH to gateway
make connect

# View logs
ssh root@YOUR_GATEWAY_IP "tail -f /var/log/gateway/*.log"

# Check WireGuard status
ssh root@YOUR_GATEWAY_IP "wg show"

# Check Mycelium status
ssh root@YOUR_GATEWAY_IP "mycelium inspect"
```

## 🧹 Cleanup

```bash
# Remove all resources
make clean

# Clear sensitive data
unset TF_VAR_mnemonic
```

## 🎯 Example Use Cases

### Web Application
- Gateway: Load balancer + SSL termination
- Internal VMs: Application servers
- Access: `https://your-domain.com`

### API Services
- Gateway: API gateway with routing
- Internal VMs: Microservices
- Access: `https://api.your-domain.com/v1/users`

### Database Cluster
- Gateway: Connection proxy
- Internal VMs: Database nodes
- Access: `mysql://gateway-ip:3306`

## 📚 Next Steps

- Read [docs/deployment.md](deployment.md) for architecture details
- Check [docs/README.md](../README.md) for advanced configuration
- Visit [platform/README.md](platform/README.md) for Ansible customization

## ❓ Troubleshooting

**Deployment fails?**
```bash
# Check Terraform logs
tofu -chdir=infrastructure plan

# Check Ansible verbose output
make ansible  # Add -vvv to debug
```

**Can't access services?**
```bash
# Test gateway connectivity
curl http://YOUR_GATEWAY_IP/

# Check firewall rules
ssh root@YOUR_GATEWAY_IP "nft list ruleset"
```

**Need help?**
- Check [docs/troubleshooting.md](troubleshooting.md)
- File issues on GitHub
- Join ThreeFold community

---

**🎉 Congratulations!** You now have a fully functional IPv4 gateway providing internet access to your IPv6-only VMs on ThreeFold Grid!