# SSL/TLS Setup Guide for ThreeFold Grid Gateway

This guide explains how to set up SSL/TLS certificates for your ThreeFold Grid Gateway using Let's Encrypt and a domain name.

## Prerequisites

- ✅ **A registered domain name** (e.g., `mygateway.example.com`)
- ✅ **Access to your domain's DNS settings**
- ✅ **Your gateway's public IPv4 address** from ThreeFold Grid
- ✅ **`GATEWAY_TYPE=gateway_proxy`** (REQUIRED for SSL - see troubleshooting below)

## Step 1: Domain Setup

### 1.1 Register a Domain Name

If you don't have a domain name yet:
- Use any domain registrar (Namecheap, GoDaddy, etc.)
- Choose a `.com`, `.org`, `.net`, or any TLD you prefer
- Keep costs low - basic domains are ~$10-15/year

### 1.2 Configure DNS A Record

Point your domain to your gateway's IPv4 address:

1. **Get your gateway's IPv4 address:**
   ```bash
   make address
   # Look for the "Gateway Public IPv4" in the output
   ```

2. **Add A record in your DNS settings:**
   - **Type:** A
   - **Name/Host:** @ (or your subdomain like `gateway`)
   - **Value:** Your gateway's IPv4 address (e.g., `185.206.122.150`)
   - **TTL:** 300 (5 minutes) or default

3. **Verify DNS propagation:**
   ```bash
   # Replace mygateway.example.com with your domain
   nslookup mygateway.example.com

   # Or use dig
   dig mygateway.example.com A
   ```

**Example DNS Configuration:**
```
Domain: mygateway.example.com
Type: A
Name: @
Value: 185.206.122.150
TTL: 300
```

## Step 2: SSL Deployment

### 2.1 Configure SSL Settings

#### Option A: Use .env file (Recommended)
```bash
# Copy the example configuration
cp .env.example .env

# Edit your SSL settings
nano .env

# Uncomment and modify these lines:
# DOMAIN_NAME=mygateway.example.com
# ENABLE_SSL=true
# GATEWAY_TYPE=gateway_proxy  # Required for SSL!
# SSL_EMAIL=admin@mygateway.example.com
```

#### Option B: Use environment variables
```bash
# Set your domain name
export DOMAIN_NAME=mygateway.example.com
export ENABLE_SSL=true
export GATEWAY_TYPE=gateway_proxy
export SSL_EMAIL=admin@mygateway.example.com
```

### 2.2 Deploy with SSL

#### Option A: Complete SSL Deployment (Recommended)
```bash
# Deploys infrastructure + gateway + SSL in one command
make ssl-demo
```

#### Option B: Step-by-Step SSL Deployment
```bash
# 1. Deploy infrastructure
make infrastructure

# 2. Generate inventory
make inventory

# 3. Deploy with SSL
make ssl-demo
```

#### Option C: Add SSL to Existing Deployment
```bash
# If you already have a deployed gateway:
make ssl-setup
```

### SSL Commands Explained

| Command | When to Use | What it Does |
|---------|-------------|--------------|
| `make ssl-demo` | **Fresh deployments** | Deploys everything with SSL from start |
| `make ssl-setup` | **Existing deployments** | Adds SSL to already deployed gateway |
| `make demo` | **No SSL needed** | Regular deployment without SSL |

**Important:** Both `ssl-demo` and `ssl-setup` require `GATEWAY_TYPE=gateway_proxy`

### 2.3 Verify SSL Setup

```bash
# Test HTTP (should redirect to HTTPS)
curl -I http://mygateway.example.com

# Test HTTPS
curl -I https://mygateway.example.com

# Check certificate details
openssl s_client -connect mygateway.example.com:443 -servername mygateway.example.com < /dev/null 2>/dev/null | openssl x509 -noout -dates -issuer -subject
```

## Step 3: Troubleshooting

### DNS Issues
```bash
# Check if domain resolves to correct IP
nslookup mygateway.example.com

# Test connectivity to your domain
ping mygateway.example.com

# Check if port 80 is accessible
curl -I http://mygateway.example.com
```

### SSL Certificate Issues
```bash
# Check certbot status on gateway
ssh root@gateway_ip "certbot certificates"

# Renew certificates manually
ssh root@gateway_ip "certbot renew"

# Check nginx configuration
ssh root@gateway_ip "nginx -t"
```

### Common Problems

1. **DNS not propagated**: Wait 5-30 minutes for DNS changes to propagate
2. **Certificate failed**: Ensure domain resolves to gateway IP before deploying SSL
3. **Port 80 blocked**: ThreeFold Grid blocks non-standard ports, but port 80 works
4. **Firewall issues**: Check that port 80 is allowed in your gateway firewall rules
5. **Wrong gateway type**: SSL requires `gateway_proxy` - see troubleshooting below

### Gateway Type Issues

**Problem:** Getting error "SSL requires gateway_proxy for SSL termination"

**Solution:**
```bash
# 1. Check your current gateway type
grep GATEWAY_TYPE .env

# 2. Update to gateway_proxy if needed
echo "GATEWAY_TYPE=gateway_proxy" >> .env

# 3. Redeploy with new gateway type
make demo

# 4. Now SSL setup will work
make ssl-setup
```

**Why gateway_proxy is required:**
- `gateway_nat`: Uses port forwarding only (no SSL termination)
- `gateway_proxy`: Uses nginx reverse proxy (handles SSL certificates)

**Quick fix for existing deployments:**
```bash
# Change gateway type and redeploy
sed -i 's/GATEWAY_TYPE=.*/GATEWAY_TYPE=gateway_proxy/' .env
make demo
make ssl-setup
```

## Step 4: Advanced Configuration

### Custom SSL Settings

Edit the nginx template at `platform/roles/gateway_proxy/templates/nginx-gateway.conf.j2`:

```nginx
# Add HSTS header for better security
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

# OCSP Stapling for better performance
ssl_stapling on;
ssl_stapling_verify on;
ssl_trusted_certificate /etc/letsencrypt/live/{{ domain_name }}/chain.pem;
```

### Multiple Domains

For multiple domains (SAN certificate):
```bash
export DOMAIN_NAME="mygateway.example.com,www.mygateway.example.com"
```

### Wildcard Certificates

For subdomains:
```bash
export DOMAIN_NAME="*.mygateway.example.com"
# Note: Requires DNS-01 challenge, not HTTP-01
```

## Security Best Practices

1. **Keep certificates updated**: Let's Encrypt certificates auto-renew
2. **Monitor certificate expiry**: Set up alerts for certificate expiration
3. **Use strong ciphers**: The template includes secure cipher suites
4. **Enable HSTS**: Consider adding HSTS headers for better security
5. **Regular security audits**: Periodically check your SSL configuration

## Cost Breakdown

- **Domain registration**: $10-15/year
- **SSL certificates**: FREE (Let's Encrypt)
- **DNS hosting**: Often included with domain, or $5-10/year
- **Total annual cost**: $15-30/year

## Next Steps

After SSL is working:
1. Update your documentation to reflect HTTPS URLs
2. Configure any monitoring tools to check HTTPS endpoints
3. Set up automated certificate renewal monitoring
4. Consider adding SSL to your internal VM services if needed

## Support

If you encounter issues:
1. Check the troubleshooting section above
2. Verify your DNS configuration
3. Ensure your domain resolves to the correct IP
4. Check gateway logs: `ssh root@gateway_ip "journalctl -u nginx"`
5. Test with online SSL checkers like SSL Labs: https://www.ssllabs.com/ssltest/