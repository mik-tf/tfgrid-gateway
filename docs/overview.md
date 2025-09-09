# Implementing a Gateway VM on ThreeFold Grid: Enabling Public Internet Access for IPv6-Only VMs

## 1. Introduction to ThreeFold Grid Networking Capabilities

The **ThreeFold Grid** offers a decentralized infrastructure platform that enables users to deploy virtual machines with **flexible networking options**, including public IPv4 addresses, IPv6 connectivity, **Mycelium** network integration, and **WireGuard** VPN capabilities. These features allow a single VM with IPv4 to function as a **network gateway** for other VMs without public IPv4 addresses, enabling protocol translation, traffic routing, and secure network tunnels .

Through the ThreeFold Grid, users can deploy VMs with **dedicated public IPv4 addresses** while utilizing the built-in **Mycelium network** (an end-to-end encrypted IPv6 overlay) for secure internal communication. The platform's native support for **WireGuard** enables secure point-to-point tunnels, while Mycelium provides a peer-to-peer mesh networking capability with **cryptographically generated IPv6 addresses** . These components can be combined to create sophisticated gateway architectures that bridge between public IPv4 internet and internal IPv6-only resources.

The key advantage of this approach is that it allows workloads running on IPv6-only VMs to be accessible via the public internet through the gateway VM, significantly reducing the need for expensive public IPv4 addresses while maintaining security through encryption and proper network segmentation .

## 2. Understanding Gateway Implementation Approaches

### 2.1 Network Address Translation (NAT)

**NAT** operates at the network layer (Layer 3) and provides **transparent routing** of traffic between networks by modifying source and/or destination addresses in IP packet headers. On ThreeFold Grid VMs, NAT can be implemented using:

- **nftables**: The modern Linux firewall and NAT system that offers **unified syntax** for all address families (IPv4, IPv6) 
- **Stateless NAT**: For 1:1 mappings with higher performance but less flexibility 
- **Stateful NAT**: Using connection tracking for dynamic scenarios, which is the recommended approach for most use cases 

NAT is particularly useful for **outbound internet access**, **port forwarding**, and **hiding internal network topology**. It's ideal for scenarios where you need to make internal services accessible on the public internet without modifying the applications themselves .

### 2.2 Proxy-Based Solutions

**Proxies** operate at application layers (Layer 4-7) and provide **content-aware routing** capabilities. For ThreeFold Grid gateways, relevant proxy approaches include:

- **Reverse proxies**: For HTTP/HTTPS traffic load balancing and termination
- **TCP/UDP proxies**: For protocol-agnostic forwarding of traffic
- **Application-specific proxies**: For specialized protocols like DNS, SIP, or database connections

Proxies offer **advantages** in content filtering, caching, and application-layer security but require **more resources** than NAT solutions and are **protocol-specific** in many cases.

### 2.3 Comparison of Approaches

*Table: NAT vs. Proxy Gateway Characteristics for ThreeFold Grid*
| **Characteristic** | **NAT** | **Proxy** |
|----------------|-----------|-----------|
| **OSI Layer** | Layer 3 | Layers 4-7 |
| **Protocol Awareness** | Limited | High |
| **Performance** | Higher throughput | More processing overhead |
| **Configuration** | Packet-based rules | Application-specific settings |
| **Security** | Connection tracking | Content inspection |
| **Use Cases** | General routing, IP masking | Load balancing, caching, SSL termination |

For most ThreeFold Grid deployments where the goal is to expose multiple services from IPv6-only VMs, a **hybrid approach** using both NAT for general traffic and proxies for specific applications often provides the best balance of performance and functionality.

## 3. nftables NAT Configuration for ThreeFold Grid Gateways

### 3.1 Basic NAT Setup with nftables

**nftables** provides a modern framework for implementing NAT on Linux-based systems, including ThreeFold Grid VMs. Below is a basic configuration for enabling **stateful NAT** on a gateway VM:

```bash
# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 1 > /proc/sys/net/ipv6/conf/all/forwarding

# Create a NAT table
nft add table ip nat

# Create prerouting and postrouting chains
nft 'add chain ip nat prerouting { type nat hook prerouting priority -100; }'
nft 'add chain ip nat postrouting { type nat hook postrouting priority 100; }'

# Enable masquerading for outbound traffic from internal network
nft add rule ip nat postrouting ip saddr 10.1.0.0/16 oif eth0 masquerade
```

This configuration enables **IP masquerading** for a private network (10.1.0.0/16), allowing internal IPv6-only hosts to access external IPv4 networks through the gateway's public IP .

### 3.2 Port Forwarding with DNAT

**Destination NAT (DNAT)** allows redirecting incoming IPv4 traffic to internal IPv6 hosts. This is essential for hosting services behind a gateway:

```bash
# Redirect HTTP/HTTPS traffic to an internal IPv6 server
nft add rule ip nat prerouting iif eth0 tcp dport { 80, 443 } dnat to 400::100:0:0:1

# Redirect SSH traffic to an internal IPv6 host
nft add rule ip nat prerouting tcp dport 22 dnat to 400::100:0:0:2
```

For **IPv6-to-IPv4 translation**, you can use the inet family which handles both IPv4 and IPv6:

```bash
# Create a dual-stack NAT table
nft add table inet nat

# Add DNAT rule for IPv4 to IPv6 translation
nft add rule inet nat prerouting iif eth0 tcp dport 80 dnat ip6 to 400::100:0:0:1
```

### 3.3 NAT with Port Range Translation

For **advanced scenarios**, nftables supports port range mapping and NAT pooling:

```bash
# NAT with source port mapping for multiple internal hosts
nft add rule ip nat postrouting ip protocol tcp snat to 10.0.0.1-10.0.0.10:30000-40000

# NAT pooling with multiple addresses
nft add rule ip nat postrouting snat to 10.0.0.2/31
```

These configurations enable **load distribution** across multiple internal hosts and **port randomization** for enhanced privacy .

## 4. WireGuard VPN Integration for Secure Gateway Services

### 4.1 Deploying WireGuard on ThreeFold Grid

**WireGuard** provides a secure VPN solution that can be integrated with ThreeFold Grid deployments. The Terraform configuration below sets up a WireGuard-based gateway between VMs:

```hcl
resource "grid_network" "net1" {
  name        = "wg-gateway"
  nodes       = [var.tfnodeid1, var.tfnodeid2]
  ip_range    = "10.1.0.0/16"
  description = "WireGuard gateway network"
  add_wg_access = true  # Enable WireGuard access
}

resource "grid_deployment" "gateway" {
  name         = "wg-gateway"
  node         = var.tfnodeid1
  network_name = grid_network.net1.name
  vms {
    name       = "gateway-vm"
    flist      = "https://hub.grid.tf/tf-official-vms/ubuntu-22.04.flist"
    cpu        = 2
    memory     = 4096
    env_vars = {
      SSH_KEY = var.SSH_KEY
    }
    publicip   = true  # Request public IPv4
    planetary = true   # Enable Mycelium Network
  }
}

resource "grid_deployment" "internal_vm" {
  name         = "internal-vm"
  node         = var.tfnodeid2
  network_name = grid_network.net1.name
  vms {
    name       = "internal-vm"
    flist      = "https://hub.grid.tf/tf-official-vms/ubuntu-22.04.flist"
    cpu        = 2
    memory     = 2048
    env_vars = {
      SSH_KEY = var.SSH_KEY
    }
    planetary = true   # Enable Mycelium but no public IPv4
  }
}
```

This configuration creates a **virtual private network** with WireGuard access, allowing secure connectivity between the gateway VM with public IPv4 and internal VMs without public IPv4 .

### 4.2 Configuring WireGuard Tunnel Interface

After deployment, extract the **WireGuard configuration** from Terraform outputs:

```bash
# Create WireGuard configuration file
mkdir -p /etc/wireguard/
terraform output wg_config > /etc/wireguard/wg0.conf

# Start WireGuard interface
wg-quick up wg0
```

The generated configuration includes **secure key pairs** and **peer definitions** that establish an encrypted tunnel between the gateway VM and internal VMs, enabling **secure access** to internal resources .

### 4.3 Routing Traffic Through WireGuard

With WireGuard established, configure **routing rules** to direct traffic through the tunnel:

```bash
# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1

# Add NAT rules for WireGuard traffic
nft add rule ip nat postrouting oifname "wg0" masquerade

# Route specific subnets through WireGuard
ip route add 10.1.0.0/16 dev wg0
```

This setup allows the gateway VM to **securely forward** traffic from the public internet to internal VMs through the encrypted WireGuard tunnel .

## 5. Leveraging Mycelium for Secure IPv6 Communication

### 5.1 Understanding Mycelium Network

**Mycelium** is ThreeFold's end-to-end encrypted IPv6 overlay network that replaces the earlier Yggdrasil implementation. Key features include:

- **End-to-end encryption**: All traffic is automatically encrypted between nodes 
- **Cryptographic addressing**: IPv6 addresses are derived from node key pairs 
- **Locality awareness**: Finds the shortest path between nodes based on latency 
- **Self-healing routing**: Automatically reroutes traffic if links fail 

Mycelium addresses the scalability limitations of Yggdrasil while maintaining backward compatibility with the core concepts of encrypted overlay networking .

### 5.2 Enabling Mycelium on ThreeFold Grid VMs

When deploying VMs on ThreeFold Grid, enable the **Mycelium** option in the network configuration:

```hcl
vms {
  name       = "mycelium-gateway"
  flist      = "https://hub.grid.tf/tf-official-vms/ubuntu-22.04.flist"
  cpu        = 2
  memory     = 2048
  planetary  = true  # Enable Mycelium network
}

vms {
  name       = "internal-vm"
  flist      = "https://hub.grid.tf/tf-official-vms/ubuntu-22.04.flist"
  cpu        = 2
  memory     = 2048
  planetary  = true  # Enable Mycelium network
  # No public IPv4 address
}
```

This enables the **Mycelium networking stack** on both VMs, providing them with **cryptographic IPv6 addresses** in the 400::/7 range that remain persistent and reachable through the Mycelium network .

### 5.3 Gateway Services over Mycelium

With Mycelium enabled, services can be exposed directly through the **encrypted overlay network** without needing public IPv4 addresses:

```bash
# On internal VM: Start web server listening on Mycelium address
python3 -m http.server 8080 --bind $(mycelium inspect --json | jq -r .address)

# On gateway VM: Set up DNAT from IPv4 to Mycelium IPv6
nft add rule inet nat prerouting iif eth0 tcp dport 80 dnat ip6 to 400::100:0:0:1:8080
```

This approach enables **secure exposure** of services running on IPv6-only VMs to the public IPv4 internet through the gateway VM, with all traffic between VMs protected by Mycelium's end-to-end encryption .

## 6. Proxy-Based Gateway Implementations

### 6.1 HTTP/HTTPS Reverse Proxy with Nginx

For **web traffic**, a reverse proxy provides advanced routing capabilities:

```nginx
# /etc/nginx/sites-available/gateway
server {
    listen 80;
    listen [::]:80;
    server_name gateway.example.com;

    # Proxy to internal HTTP service over Mycelium
    location / {
        proxy_pass http://[400::100:0:0:1]:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Proxy to internal HTTPS service
    location /app {
        proxy_pass https://[400::100:0:0:2]:443;
        proxy_ssl_verify off;
    }
}
```

This configuration provides **layer 7 routing** based on URL paths, offering more flexibility than NAT for HTTP-based services while maintaining end-to-end security through Mycelium's encryption.

### 6.2 TCP/UDP Proxy with HAProxy

For **non-HTTP services**, HAProxy provides robust TCP/UDP proxying:

```haproxy
# /etc/haproxy/haproxy.cfg
frontend ssh_frontend
    bind :2222
    mode tcp
    option tcplog
    default_backend ssh_backend

backend ssh_backend
    mode tcp
    server ssh_server1 [400::100:0:0:1]:22 check

frontend dns_udp_frontend
    bind :53
    mode udp
    default_backend dns_udp_backend

backend dns_udp_backend
    mode udp
    server dns_server [400::100:0:0:3]:53 check
```

This setup allows **load balancing** and **protocol translation** for TCP and UDP services, which is particularly useful for applications that don't work well with NAT.

### 6.3 Protocol-Specific Proxies

For **specialized protocols**, consider these proxy solutions:

- **DNS**: dnsmasq or bind9 for DNS forwarding and caching
- **Database**: pgpool-II for PostgreSQL or MySQL Proxy for MySQL
- **SFTP/SCP**: sshd built-in port forwarding or specialized tools like rssh
- **VoIP**: Kamailio or Asterisk for SIP protocol routing

These **application-aware proxies** provide better functionality than generic NAT rules for specialized protocols while leveraging Mycelium for secure internal communication.

## 7. Implementation Guidance and Best Practices

### 7.1 Deploying Gateway VMs on ThreeFold Grid

When deploying gateway VMs on ThreeFold Grid, follow these steps:

1.  **Select appropriate capacity**: Choose a VM size based on expected traffic
    - Small: 1 vCPU, 2GB RAM, 25GB storage for light traffic
    - Medium: 2 vCPU, 4GB RAM, 50GB storage for moderate traffic
    - Large: 4 vCPU, 8GB RAM, 100GB storage for heavy traffic

2.  **Enable networking features**:
    - Public IPv4 for direct internet accessibility
    - Planetary Network (Mycelium) for secure internal communication
    - WireGuard Access for secure tunnels if needed 

3.  **Configure security**:
    - Set up firewall rules (using nftables)
    - Allow only necessary ports (SSH, HTTP, HTTPS, etc.)
    - Implement rate limiting for public services

### 7.2 Security Considerations

Implement **defense-in-depth** for gateway VMs:

```bash
# Basic nftables firewall for gateway
table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;
        
        # Allow established connections
        ct state established,related accept
        
        # Allow loopback
        iif lo accept
        
        # Allow SSH from specific networks
        ip saddr { 192.168.1.0/24, 10.0.0.0/8 } tcp dport 22 accept
        
        # Allow HTTP/HTTPS from anywhere
        tcp dport { 80, 443 } accept
        
        # Log and drop everything else
        log prefix "Dropped input: " drop
    }
    
    chain forward {
        type filter hook forward priority 0; policy drop;
        
        # Allow forwarded traffic from internal network
        iif wg0 oif eth0 accept
        iif eth0 oif wg0 ct state established,related accept
        
        # Log and drop everything else
        log prefix "Dropped forward: " drop
    }
}
```

This configuration provides **stateful filtering** and **logging** for both input and forwarded traffic, ensuring only authorized traffic passes through the gateway.

### 7.3 Monitoring and Maintenance

Implement **monitoring solutions** for gateway functionality:

```bash
# Track NAT statistics with nftables
nft add chain ip nat stats { type nat hook prerouting priority -10; }
nft add rule ip nat stats counter

# Monitor connection tracking
conntrack -L -o extended

# Check WireGuard interface status
wg show all

# Check Mycelium connectivity
mycelium inspect --json
```

Set up **alerting** for abnormal traffic patterns and **regular audits** of firewall rules and proxy configurations to maintain security and performance.

## 8. Conclusion

Implementing a **gateway VM** on ThreeFold Grid with public IPv4 connectivity provides an efficient solution for exposing services from IPv6-only VMs to the public internet. By leveraging **nftables NAT** for transparent routing, **WireGuard** for secure tunnels, and **Mycelium** for encrypted internal communication, users can create robust network architectures that maximize resource utilization while maintaining security.

The choice between **NAT** and **proxy approaches** depends on specific requirements: NAT offers performance and transparency for generic routing, while proxies provide advanced functionality for specific protocols. For most deployments, a **hybrid approach** provides the best balance of performance, security, and functionality.

By utilizing the **decentralized nature** of ThreeFold Grid, these gateway solutions can be deployed globally with **redundancy** and **low latency**, providing robust network infrastructure without relying on traditional centralized cloud providers . This approach significantly reduces the need for expensive public IPv4 addresses while maintaining full connectivity for services running on IPv6-only VMs.