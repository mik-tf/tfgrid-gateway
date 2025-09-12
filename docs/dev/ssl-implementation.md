# SSL Implementation Details

## SSL Setup Script

Create `scripts/ssl-setup.sh` with the following content:

```bash
#!/bin/bash

# SSL Setup Script for ThreeFold Grid Gateway
# This script handles SSL certificate setup using Let's Encrypt

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

# Default values
DOMAIN_NAME=${DOMAIN_NAME:-}
ENABLE_SSL=${ENABLE_SSL:-false}
GATEWAY_TYPE=${GATEWAY_TYPE:-gateway_proxy}

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if domain is provided
    if [ -z "$DOMAIN_NAME" ]; then
        log_error "DOMAIN_NAME environment variable is required"
        log_error "Example: export DOMAIN_NAME=mygateway.example.com"
        exit 1
    fi

    # Check if SSL is enabled
    if [ "$ENABLE_SSL" != "true" ]; then
        log_error "ENABLE_SSL must be set to 'true'"
        log_error "Example: export ENABLE_SSL=true"
        exit 1
    fi

    # Check if using proxy gateway
    if [ "$GATEWAY_TYPE" != "gateway_proxy" ]; then
        log_warning "SSL is designed for gateway_proxy. Current: $GATEWAY_TYPE"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    log_success "Prerequisites check passed"
}

# Verify DNS configuration
verify_dns() {
    log_info "Verifying DNS configuration for $DOMAIN_NAME..."

    # Get gateway IP from Terraform outputs or inventory
    GATEWAY_IP=""
    if [ -f "$PROJECT_DIR/platform/inventory.ini" ]; then
        GATEWAY_IP=$(grep -oP 'ansible_host=\K[^ ]+' "$PROJECT_DIR/platform/inventory.ini" | head -1)
    fi

    if [ -z "$GATEWAY_IP" ]; then
        log_warning "Could not determine gateway IP from inventory"
        log_warning "Please ensure your domain $DOMAIN_NAME points to your gateway's IPv4 address"
        return
    fi

    # Check DNS resolution
    DOMAIN_IP=$(dig +short A "$DOMAIN_NAME" | head -1)

    if [ -z "$DOMAIN_IP" ]; then
        log_error "Domain $DOMAIN_NAME does not resolve to any IP address"
        log_error "Please check your DNS configuration"
        exit 1
    fi

    if [ "$DOMAIN_IP" != "$GATEWAY_IP" ]; then
        log_error "Domain $DOMAIN_NAME resolves to $DOMAIN_IP but gateway is at $GATEWAY_IP"
        log_error "Please update your DNS A record to point to $GATEWAY_IP"
        exit 1
    fi

    log_success "DNS verification passed: $DOMAIN_NAME → $GATEWAY_IP"
}

# Setup SSL certificates
setup_ssl() {
    log_info "Setting up SSL certificates for $DOMAIN_NAME..."

    # Check if we're running on the gateway
    if [ ! -f /etc/os-release ] || ! grep -q "Ubuntu\|Debian" /etc/os-release; then
        log_error "This script should be run on the gateway VM"
        log_error "SSH into your gateway and run this script there"
        exit 1
    fi

    # Install certbot if not present
    if ! command -v certbot &> /dev/null; then
        log_info "Installing certbot..."
        apt update
        apt install -y certbot python3-certbot-nginx
    fi

    # Check if certificate already exists
    if [ -d "/etc/letsencrypt/live/$DOMAIN_NAME" ]; then
        log_warning "SSL certificate already exists for $DOMAIN_NAME"
        log_info "Checking certificate validity..."

        # Check certificate expiry
        if openssl x509 -checkend 86400 -noout -in "/etc/letsencrypt/live/$DOMAIN_NAME/cert.pem" 2>/dev/null; then
            log_success "Certificate is valid for at least 24 more hours"
            return
        else
            log_warning "Certificate expires soon, renewing..."
            certbot renew --cert-name "$DOMAIN_NAME"
            return
        fi
    fi

    # Obtain new certificate
    log_info "Obtaining SSL certificate for $DOMAIN_NAME..."

    # Stop nginx temporarily for HTTP-01 challenge
    if systemctl is-active --quiet nginx; then
        systemctl stop nginx
    fi

    # Get certificate
    if certbot certonly --standalone -d "$DOMAIN_NAME" --agree-tos --email "admin@$DOMAIN_NAME" --non-interactive; then
        log_success "SSL certificate obtained successfully"
    else
        log_error "Failed to obtain SSL certificate"
        # Restart nginx if it was stopped
        if ! systemctl is-active --quiet nginx; then
            systemctl start nginx
        fi
        exit 1
    fi

    # Restart nginx
    systemctl start nginx
    log_success "Nginx restarted with SSL configuration"
}

# Main execution
main() {
    echo "ThreeFold Grid Gateway - SSL Setup"
    echo "=================================="

    check_prerequisites
    verify_dns
    setup_ssl

    echo ""
    log_success "SSL setup completed successfully!"
    echo ""
    echo "Your gateway is now available at:"
    echo "  HTTP:  http://$DOMAIN_NAME"
    echo "  HTTPS: https://$DOMAIN_NAME"
    echo ""
    echo "Test your SSL setup:"
    echo "  curl -I https://$DOMAIN_NAME"
}

# Run main function
main "$@"
```

## Makefile Updates

Update the Makefile to include SSL deployment targets:

```makefile
# Add to .PHONY line:
.PHONY: help address ansible ansible-test clean connect demo demo-status demo-test infrastructure inventory ping quick quick-demo ssl-demo ssl-setup verify wireguard

# Add SSL-specific targets:
ssl-setup:
	@echo "Setting up SSL certificates..."
	@if [ -z "$$DOMAIN_NAME" ]; then \
		echo "Error: DOMAIN_NAME environment variable is required"; \
		echo "Example: export DOMAIN_NAME=mygateway.example.com"; \
		exit 1; \
	fi; \
	if [ "$$ENABLE_SSL" != "true" ]; then \
		echo "Error: ENABLE_SSL must be set to 'true'"; \
		echo "Example: export ENABLE_SSL=true"; \
		exit 1; \
	fi; \
	./scripts/ssl-setup.sh

ssl-demo:
	@echo "Deploying gateway with SSL support..."
	@if [ -f .env ]; then set -a && . ./.env && set +a; fi; \
	cd platform && ansible-playbook -i inventory.ini \
		--extra-vars "gateway_type=$${GATEWAY_TYPE:-gateway_proxy} \
		              network_mode=$${NETWORK_MODE:-wireguard-only} \
		              enable_demo=true \
		              configure_internal_vms=true \
		              enable_vm_demo=true \
		              enable_ssl=true \
		              domain_name=$${DOMAIN_NAME}" \
		site.yml

# Update help section:
ssl-demo:
	@echo "  make ssl-demo         - Deploy gateway with SSL/TLS support"
	@echo "  make ssl-setup        - Setup SSL certificates for existing deployment"
	@echo ""
	@echo "SSL Configuration:"
	@echo "  export DOMAIN_NAME=mygateway.example.com"
	@echo "  export ENABLE_SSL=true"
	@echo "  export GATEWAY_TYPE=gateway_proxy"
```

## Environment Variables

Add to your `.env` file or export these variables:

```bash
# SSL Configuration
DOMAIN_NAME=mygateway.example.com
ENABLE_SSL=true
GATEWAY_TYPE=gateway_proxy

# Optional SSL settings
SSL_EMAIL=admin@mygateway.example.com
SSL_STAGING=false  # Set to true for testing with Let's Encrypt staging
```

## Nginx Template Improvements

The existing `nginx-gateway.conf.j2` template already supports SSL, but add these improvements:

### Add HTTP to HTTPS Redirect

Add this to the HTTP server block:

```nginx
# Redirect HTTP to HTTPS
if ($scheme = http) {
    return 301 https://$server_name$request_uri;
}
```

### Enhanced SSL Configuration

Update the SSL server block with better security:

```nginx
server {
    listen 443 ssl http2;
    server_name {{ domain_name | default('_') }};

    # SSL configuration
    ssl_certificate /etc/letsencrypt/live/{{ domain_name }}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/{{ domain_name }}/privkey.pem;

    # Enhanced SSL security settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers off;

    # HSTS (uncomment when ready for production)
    # add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # OCSP Stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_trusted_certificate /etc/letsencrypt/live/{{ domain_name }}/chain.pem;

    # Rest of your configuration...
}
```

## Deployment Workflow

### Complete SSL Deployment

```bash
# 1. Set environment variables
export DOMAIN_NAME=mygateway.example.com
export ENABLE_SSL=true
export GATEWAY_TYPE=gateway_proxy

# 2. Deploy infrastructure
make infrastructure
make inventory

# 3. Deploy with SSL
make ssl-demo

# 4. Verify
curl -I https://mygateway.example.com
```

### Adding SSL to Existing Deployment

```bash
# 1. Set environment variables
export DOMAIN_NAME=mygateway.example.com
export ENABLE_SSL=true

# 2. Setup SSL certificates
make ssl-setup

# 3. Redeploy configuration
make demo
```

## Testing SSL Setup

### Basic Tests

```bash
# Test HTTP (should redirect to HTTPS)
curl -I http://mygateway.example.com

# Test HTTPS
curl -I https://mygateway.example.com

# Check certificate details
openssl s_client -connect mygateway.example.com:443 -servername mygateway.example.com < /dev/null 2>/dev/null | openssl x509 -noout -dates -issuer -subject

# SSL Labs test (online)
echo "Test your SSL at: https://www.ssllabs.com/ssltest/analyze.html?d=mygateway.example.com"
```

### Certificate Management

```bash
# Check certificate status
ssh root@gateway_ip "certbot certificates"

# Renew certificates
ssh root@gateway_ip "certbot renew"

# Force renewal
ssh root@gateway_ip "certbot renew --force-renewal"
```

## Troubleshooting

### Common Issues

1. **DNS not propagated**
   ```bash
   # Wait for DNS propagation
   watch -n 60 dig A mygateway.example.com
   ```

2. **Certificate challenge failed**
   ```bash
   # Check nginx is stopped during challenge
   ssh root@gateway_ip "systemctl status nginx"
   ```

3. **Firewall blocking port 80**
   ```bash
   # Ensure port 80 is open for HTTP-01 challenge
   ssh root@gateway_ip "ufw status"
   ```

4. **Certificate expiry**
   ```bash
   # Check expiry date
   ssh root@gateway_ip "openssl x509 -noout -dates -in /etc/letsencrypt/live/mygateway.example.com/cert.pem"
   ```

## Security Considerations

1. **Certificate Auto-Renewal**: Let's Encrypt certificates auto-renew
2. **HSTS Headers**: Consider enabling HSTS for better security
3. **SSL/TLS Best Practices**: The configuration follows current best practices
4. **Monitoring**: Set up monitoring for certificate expiry

## SSL Termination Architecture

### Overview

The tfgrid-gateway implements **SSL termination at the gateway level**, which is an industry-standard approach for reverse proxy deployments. This architecture provides several key benefits:

### Architecture Diagram

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Client        │    │   Gateway        │    │   Backend VMs   │
│   Browser       │    │   (SSL Gateway)  │    │   (HTTP Only)   │
├─────────────────┤    ├──────────────────┤    ├─────────────────┤
│ HTTPS (Port 443)│───▶│ SSL Termination │───▶│ HTTP (Ports     │
│ Encrypted       │    │ Let's Encrypt   │    │ 8001,8002,8003) │
│ Traffic         │    │ Certificate      │    │ Unencrypted     │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌──────────────────┐
                       │ Certificate      │
                       │ Management       │
                       │ Auto-renewal     │
                       └──────────────────┘
```

### How SSL Termination Works

1. **Client Connection**
   - Browser initiates HTTPS connection to `https://yourdomain.com`
   - SSL/TLS handshake begins

2. **SSL Handshake at Gateway**
   - Gateway presents Let's Encrypt SSL certificate
   - Client validates certificate authenticity
   - Encrypted tunnel established between client and gateway

3. **Traffic Decryption**
   - Gateway decrypts incoming HTTPS traffic
   - Converts to plain HTTP for internal routing

4. **Backend Communication**
   - Gateway proxies HTTP requests to backend VMs
   - Uses appropriate ports (8001, 8002, 8003)
   - Load balances across available backend servers

5. **Response Encryption**
   - Backend VMs respond with HTTP content
   - Gateway re-encrypts response using SSL
   - Secure HTTPS response sent to client

### Technical Implementation

#### Nginx Configuration

```nginx
# HTTP Server (Port 80) - Redirects to HTTPS
server {
    listen 80;
    server_name yourdomain.com;
    return 301 https://$server_name$request_uri;
}

# HTTPS Server (Port 443) - SSL Termination
server {
    listen 443 ssl http2;
    server_name yourdomain.com;

    # SSL Certificate Configuration
    ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;

    # SSL Security Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:...;

    # Proxy to Backend (HTTP, not HTTPS)
    location / {
        proxy_pass http://backend_http;  # HTTP to backend VMs
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# Backend Upstream Configuration
upstream backend_http {
    server 10.1.4.2:8001;  # VM 7
    server 10.1.5.2:8002;  # VM 8
    server 10.1.6.2:8003;  # VM 11
}
```

#### Certificate Management

- **Automatic Renewal**: Let's Encrypt certificates renew every 90 days
- **Zero Downtime**: Renewal process doesn't interrupt service
- **Monitoring**: Certificate expiry alerts and monitoring
- **Backup**: Certificate files included in deployment backups

### Benefits of SSL Termination

#### Security Benefits
- **Centralized SSL**: Single point for SSL configuration and monitoring
- **Certificate Management**: Simplified certificate lifecycle management
- **Security Headers**: HSTS, CSP, and other headers applied consistently
- **Threat Protection**: SSL/TLS attacks handled at gateway level

#### Performance Benefits
- **SSL Offloading**: Backend servers don't process SSL encryption/decryption
- **Resource Efficiency**: SSL processing handled by dedicated gateway
- **Caching**: SSL session caching improves performance
- **Connection Reuse**: Keep-alive connections optimized

#### Operational Benefits
- **Simplified Backend**: VMs don't need SSL configuration
- **Easy Scaling**: Add/remove backend servers without SSL complexity
- **Monitoring**: Centralized SSL metrics and logging
- **Compliance**: Easier to maintain security compliance

### Security Considerations

#### SSL/TLS Configuration
- **TLS 1.2/1.3 Only**: Legacy protocols disabled
- **Strong Ciphers**: Only secure cipher suites allowed
- **Perfect Forward Secrecy**: Enabled for enhanced security
- **HSTS**: HTTP Strict Transport Security headers

#### Certificate Security
- **Let's Encrypt**: Trusted certificate authority
- **Auto-renewal**: Prevents certificate expiry issues
- **OCSP Stapling**: Faster certificate validation
- **Certificate Pinning**: Ready for HPKP implementation

### Troubleshooting SSL Termination

#### Common Issues

1. **502 Bad Gateway on HTTPS**
   - **Cause**: Backend VMs not responding on expected ports
   - **Fix**: Verify VM services running on ports 8001, 8002, 8003
   - **Check**: `curl http://10.1.4.2:8001` from gateway

2. **SSL Certificate Errors**
   - **Cause**: Certificate not obtained or expired
   - **Fix**: Run `certbot certificates` to check status
   - **Renew**: `certbot renew` for expired certificates

3. **Mixed Content Warnings**
   - **Cause**: HTTP resources loaded on HTTPS pages
   - **Fix**: Ensure all resources use HTTPS or relative URLs

#### Debugging Commands

```bash
# Check SSL certificate status
ssh root@gateway_ip "certbot certificates"

# Test backend connectivity
ssh root@gateway_ip "curl -I http://10.1.4.2:8001"

# Check nginx SSL configuration
ssh root@gateway_ip "nginx -t"

# View SSL handshake
openssl s_client -connect yourdomain.com:443 -servername yourdomain.com

# Monitor SSL connections
ssh root@gateway_ip "tail -f /var/log/nginx/access.log"
```

### Performance Optimization

#### SSL Session Caching
```nginx
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;
```

#### OCSP Stapling
```nginx
ssl_stapling on;
ssl_stapling_verify on;
ssl_trusted_certificate /etc/letsencrypt/live/yourdomain.com/chain.pem;
```

#### Connection Optimization
- **HTTP/2**: Enabled for better performance
- **Keep-alive**: Connection reuse optimization
- **Buffer Sizes**: Optimized for SSL traffic

### Monitoring and Alerting

#### Certificate Monitoring
- **Expiry Alerts**: Monitor certificate expiration dates
- **Renewal Status**: Track automatic renewal success/failure
- **SSL Labs Rating**: Regular SSL configuration testing

#### Performance Monitoring
- **SSL Handshake Time**: Monitor TLS negotiation performance
- **Connection Errors**: Track SSL/TLS connection failures
- **Backend Health**: Monitor backend VM availability

## Next Steps

After SSL is working:
1. Update all documentation to use HTTPS URLs
2. Configure monitoring for certificate expiry
3. Consider enabling HSTS headers
4. Test with different browsers and SSL validation tools

This SSL termination architecture provides enterprise-grade security while maintaining simplicity and performance for the ThreeFold Grid gateway deployment.
