# Nexus IQ Server GCP Infrastructure

This directory contains Terraform configuration for deploying Nexus IQ Server on Google Cloud Platform (GCP) using Cloud Run, Cloud SQL, and other native GCP services as part of a **Reference Architecture for Native Cloud Deployments**.

## Architecture Overview

This infrastructure deploys a complete, production-ready Nexus IQ Server environment including:

- **Cloud Run** - Serverless containerized Nexus IQ Server deployment with autoscaling
- **Global Load Balancer** - HTTP(S) load balancer with health checks and optional Cloud Armor protection
- **Cloud SQL PostgreSQL** - Managed database with high availability options and automated backups
- **Cloud Filestore** - Managed NFS for shared persistent storage (`/sonatype-work`)
- **VPC & Networking** - Custom VPC with public/private subnets and VPC connectors
- **Security** - VPC firewall rules, service accounts, and IAM policies following least-privilege principles
- **Secret Manager** - Secure database credential storage
- **Cloud Logging & Monitoring** - Comprehensive observability with dashboards and alerting

```
Internet
    ↓
Global Load Balancer (with Cloud Armor)
    ↓
Cloud Run Service (Private, Autoscaling) ←→ Cloud Filestore (NFS)
    ↓
Cloud SQL PostgreSQL (Private, HA Optional)
```

## Deployment Modes

### Single Instance Mode (`iq_deployment_mode = "single"`)
- **Recommended for**: Development, testing, small to medium organizations (up to 100 applications)
- **Resources**: 1 Cloud Run instance (min/max), single-zone Cloud SQL
- **Cost**: ~$200-300/month

### High Availability Mode (`iq_deployment_mode = "ha"`)  
- **Recommended for**: Production, large organizations (100+ applications)
- **Resources**: 2-10 Cloud Run instances, regional Cloud SQL with optional read replicas
- **Cost**: ~$400-600/month

## Prerequisites

### Required Tools
- **Terraform** >= 1.0
- **Google Cloud SDK** (gcloud CLI)
- **jq** (for JSON processing in scripts)

### GCP Requirements
- GCP project with billing enabled
- Required APIs will be enabled automatically
- Authenticated gcloud CLI (`gcloud auth login`)

## Quick Start

### 1. Navigate to the GCP infrastructure directory
```bash
cd /path/to/sca-example-terraform/infra-gcp
```

### 2. Run the automated deployment script
```bash
./deploy.sh
```

This script will:
- Check prerequisites and authenticate with GCP
- Enable required APIs
- Create a `terraform.tfvars` template if it doesn't exist
- Guide you through the configuration
- Deploy the complete infrastructure
- Provide access information

### 3. Access your Nexus IQ Server
- Get the application URL from the script output
- Wait 5-10 minutes for the service to be ready
- Default credentials: `admin` / `admin123`

## Manual Deployment

### 1. Configure Variables

Create and edit `terraform.tfvars`:

```hcl
# GCP Configuration
gcp_project_id = "your-project-id"
gcp_region     = "us-central1"
gcp_zone       = "us-central1-a"

# Environment
environment = "dev"

# Deployment Mode: "single" or "ha"
iq_deployment_mode = "single"

# Database Configuration
db_password = "YourSecurePassword123!"

# Networking
vpc_connector_cidr = "10.0.4.0/28"

# Optional: Domain and SSL
# domain_name = "nexus-iq.example.com"
# ssl_certificate_name = "nexus-iq-ssl-cert"

# Optional: Monitoring alerts
# alert_email_addresses = ["admin@example.com"]

# Security
enable_cloud_armor = true
rate_limit_threshold = 100

# Storage
storage_force_destroy = false  # Set to true for testing only
```

### 2. Plan and Deploy

```bash
# Initialize Terraform
terraform init

# Plan deployment
./gcp-plan.sh

# Apply changes
./gcp-apply.sh

# Or use terraform directly
terraform apply -var-file=terraform.tfvars
```

### 3. Access Information

```bash
# Get all outputs
terraform output

# Get application URL
terraform output application_url

# Get access information
terraform output access_information
```

## Configuration Options

### Deployment Modes

**Single Instance**:
```hcl
iq_deployment_mode = "single"
iq_min_instances_single = 1
iq_max_instances_single = 1
```

**High Availability**:
```hcl
iq_deployment_mode = "ha"
iq_min_instances_ha = 2
iq_max_instances_ha = 10
enable_read_replica = true
```

### Resource Sizing

**Cloud Run**:
```hcl
iq_cpu = "2"           # CPU cores
iq_memory = "4Gi"      # Memory allocation
iq_max_concurrency = 1000  # Requests per instance
```

**Database**:
```hcl
db_instance_tier = "db-custom-2-4096"  # 2 vCPU, 4GB RAM
db_allocated_storage = 100             # Initial storage in GB
db_max_allocated_storage = 1000        # Auto-scaling limit
```

**Storage**:
```hcl
filestore_tier = "BASIC_SSD"      # BASIC_HDD, BASIC_SSD, HIGH_SCALE_SSD
filestore_capacity_gb = 1024      # Minimum 1TB for BASIC tiers
```

### Security Configuration

**Cloud Armor**:
```hcl
enable_cloud_armor = true
rate_limit_threshold = 100  # Requests per minute per IP
```

**SSL/TLS**:
```hcl
ssl_certificate_name = "nexus-iq-ssl-cert"  # Managed certificate name
domain_name = "nexus-iq.example.com"
```

**Network Security**:
```hcl
enable_ssh_access = false  # For debugging only
ssh_source_ranges = ["10.0.0.0/8"]  # Restrict SSH access
```

## Available Scripts

### Deployment Scripts

- **`./deploy.sh`** - Complete infrastructure deployment with prerequisites check
- **`./gcp-plan.sh`** - Plan Terraform changes with authentication and validation
- **`./gcp-apply.sh`** - Apply Terraform changes with confirmation
- **`./destroy.sh`** - Safely destroy infrastructure with backup options

### Script Features

- **Authentication handling** - Automatic gcloud authentication verification
- **Prerequisites checking** - Validates tools and permissions
- **Configuration validation** - Ensures required variables are set
- **Interactive confirmations** - Prevents accidental operations
- **Comprehensive logging** - Detailed logs for troubleshooting
- **Resource cleanup** - Proper cleanup of temporary files

## Management and Operations

### Accessing the Application

```bash
# Get application URL
terraform output application_url

# Check service status
gcloud run services describe $(terraform output -raw cloud_run_service_name) \
  --region=$(terraform output -raw region)

# View application logs
gcloud run services logs tail $(terraform output -raw cloud_run_service_name) \
  --region=$(terraform output -raw region)
```

### Database Operations

```bash
# Connect to database (requires Cloud SQL Proxy)
gcloud sql connect $(terraform output -raw database_instance_name) --user=nexusiq

# Create database backup
gcloud sql backups create --instance=$(terraform output -raw database_instance_name)

# List backups
gcloud sql backups list --instance=$(terraform output -raw database_instance_name)
```

### Monitoring and Alerting

```bash
# View monitoring dashboard
echo "Dashboard URL: $(terraform output -raw monitoring_dashboard_url)"

# Check uptime status
gcloud monitoring uptime list

# View recent alerts
gcloud alpha monitoring policies list
```

### Scaling Operations

**Horizontal Scaling (HA mode)**:
```hcl
# Edit terraform.tfvars
iq_min_instances_ha = 3
iq_max_instances_ha = 15

# Apply changes
terraform apply -var-file=terraform.tfvars
```

**Vertical Scaling**:
```hcl
# Edit terraform.tfvars
iq_cpu = "4"
iq_memory = "8Gi"
```

## Security Features

- **VPC Isolation**: Services run in private subnets with no direct internet access
- **Database Security**: Cloud SQL in private IP space with encryption at rest
- **Secrets Management**: Database credentials stored in Secret Manager
- **Network Security**: VPC firewall rules following least-privilege principles
- **Service Accounts**: Dedicated service accounts with minimal required permissions
- **Cloud Armor**: DDoS protection and web application firewall
- **Encryption**: Data encrypted in transit and at rest across all services

## High Availability Features

- **Multi-zone deployment**: Resources distributed across availability zones
- **Autoscaling**: Cloud Run instances scale based on demand
- **Database HA**: Regional Cloud SQL with automatic failover
- **Load balancing**: Global load balancer with health checks
- **Backup and recovery**: Automated database backups with point-in-time recovery
- **Monitoring**: Comprehensive alerting on service health and performance

## Cost Optimization

### Estimated Monthly Costs

**Single Instance Mode**:
- Cloud Run (2 vCPU, 4GB): ~$30-50
- Cloud SQL (2 vCPU, 4GB): ~$70-90
- Cloud Filestore (1TB): ~$200
- Load balancer & networking: ~$30-50
- **Total: ~$330-390/month**

**High Availability Mode**:
- Cloud Run (2-10 instances): ~$60-200
- Cloud SQL (Regional, larger): ~$140-280
- Cloud Filestore (1TB): ~$200
- Load balancer & networking: ~$50-70
- **Total: ~$450-750/month**

### Cost Optimization Tips

1. **Right-size resources** based on actual usage
2. **Use committed use discounts** for predictable workloads
3. **Enable autoscaling** to scale down during low usage
4. **Monitor storage usage** and clean up old backups
5. **Use preemptible instances** for non-critical workloads (if applicable)

## Networking

### Subnets and IP Ranges

- **Public Subnet**: `10.0.1.0/24` (Load balancer only)
- **Private Subnet**: `10.0.2.0/24` (Cloud Run services)
- **Database Subnet**: `10.0.3.0/24` (Cloud SQL)
- **VPC Connector**: `10.0.4.0/28` (Cloud Run to VPC communication)

### Firewall Rules

- **allow-lb-access**: HTTP/HTTPS from internet to load balancer
- **allow-health-checks**: Google health checks to services
- **allow-cloudsql-access**: Cloud Run to database communication
- **allow-filestore-access**: NFS access to Cloud Filestore
- **allow-internal**: Internal VPC communication

## Monitoring and Observability

### Built-in Monitoring

- **Cloud Monitoring Dashboard**: Service metrics and health
- **Uptime Checks**: Application availability monitoring
- **Log Aggregation**: Centralized logging in Cloud Logging
- **Alert Policies**: CPU, memory, error rate, and database alerts
- **SLO Monitoring**: Service level objective tracking

### Custom Metrics

- **Application-specific metrics**: Business logic monitoring
- **Performance metrics**: Response times and throughput
- **Error tracking**: Application errors and exceptions

## Troubleshooting

### Common Issues

**Service Not Accessible**: 
```bash
# Check Cloud Run service status
gcloud run services describe $(terraform output -raw cloud_run_service_name) \
  --region=$(terraform output -raw region)

# Check load balancer health
gcloud compute backend-services get-health $(terraform output -raw backend_service_name) \
  --global
```

**Database Connection Issues**:
```bash
# Check database status
gcloud sql instances describe $(terraform output -raw database_instance_name)

# Test database connectivity
gcloud sql connect $(terraform output -raw database_instance_name) --user=nexusiq
```

**Performance Issues**:
```bash
# Check service metrics
gcloud run services describe $(terraform output -raw cloud_run_service_name) \
  --region=$(terraform output -raw region) \
  --format="value(status.traffic[0].percent)"

# View monitoring dashboard
echo "$(terraform output -raw monitoring_dashboard_url)"
```

### Logs and Debugging

```bash
# Application logs
gcloud run services logs tail $(terraform output -raw cloud_run_service_name) \
  --region=$(terraform output -raw region) --follow

# Database logs
gcloud logging read "resource.type=cloudsql_database" --limit=50

# Load balancer logs
gcloud logging read "resource.type=http_load_balancer" --limit=50
```

## Cleanup

### Complete Infrastructure Removal

```bash
./destroy.sh
```

This script will:
- Show all resources to be deleted
- Offer backup options for data
- Require explicit confirmation
- Clean up all resources including secrets

### Partial Cleanup

```bash
# Stop Cloud Run service only (keeps data)
terraform destroy -target=google_cloud_run_v2_service.iq_service

# Remove specific resources
terraform destroy -target=google_compute_security_policy.iq_security_policy
```

## Production Considerations

For production deployments, consider these additional configurations:

### Security Hardening
```hcl
# Enable additional security features
enable_cloud_armor = true
enable_web_security_scanner = true
enable_workload_identity = true

# Restrict access
ssh_source_ranges = ["10.0.0.0/8"]  # Internal networks only
```

### High Availability
```hcl
# Enable HA mode
iq_deployment_mode = "ha"
enable_read_replica = true

# Regional database
# (automatically enabled in HA mode)
```

### Monitoring and Alerting
```hcl
# Configure alerting
alert_email_addresses = ["admin@company.com", "ops@company.com"]
alert_cpu_threshold = 0.7
alert_memory_threshold = 0.8
availability_slo_target = 0.999
```

### SSL/TLS Configuration
```hcl
# Use managed SSL certificates
ssl_certificate_name = "nexus-iq-ssl-cert"
domain_name = "nexus-iq.company.com"
```

## Support and Documentation

- **Architecture Details**: See [ARCHITECTURE.md](./ARCHITECTURE.md) for detailed system design
- **Security Guide**: See [SECURITY.md](./SECURITY.md) for security best practices
- **Monitoring Guide**: See [MONITORING.md](./MONITORING.md) for observability setup

For issues with this infrastructure:
1. Check the troubleshooting section above
2. Review GCP service logs and monitoring
3. Consult the [Nexus IQ Server documentation](https://help.sonatype.com/iqserver)
4. Review [Terraform GCP Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## File Structure

```
infra-gcp/
├── main.tf              # Core GCP resources, VPC, networking
├── compute.tf           # Cloud Run service configuration
├── database.tf          # Cloud SQL database and secrets
├── storage.tf           # Cloud Filestore and storage buckets
├── load_balancer.tf     # Global load balancer and health checks
├── iam.tf               # Service accounts and IAM policies
├── security.tf          # VPC firewall rules and security
├── monitoring.tf        # Cloud Logging and Monitoring
├── variables.tf         # Input variable definitions
├── outputs.tf           # Output value definitions
├── terraform.tfvars     # Configuration values (created by deploy.sh)
├── deploy.sh           # Complete deployment script
├── destroy.sh          # Safe destruction script
├── gcp-plan.sh         # Planning script
├── gcp-apply.sh        # Apply script
├── README.md           # This file
├── ARCHITECTURE.md     # Detailed architecture documentation
├── SECURITY.md         # Security best practices
└── MONITORING.md       # Monitoring and observability guide
```