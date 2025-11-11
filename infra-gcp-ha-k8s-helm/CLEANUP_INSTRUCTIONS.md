# Manual Cleanup Instructions for GCP GKE HA

When you get the "Producer services are still using this connection" error during `terraform destroy`, it means Cloud SQL or other services are still using the VPC service connection.

## Quick Fix (Recommended)

Run the automated cleanup script:

```bash
./force-cleanup.sh
```

This will:
1. Delete all Cloud SQL instances with "nexus-iq-ha" prefix
2. Wait for deletion to complete
3. Clean up Terraform state
4. Run terraform destroy

## Manual Cleanup (If Script Fails)

### Step 1: Identify and Delete Cloud SQL Instances

```bash
# List all SQL instances in the project
gcloud sql instances list --project=nxrm-support-gcp-deployments

# Delete any nexus-iq-ha instances
gcloud sql instances delete INSTANCE_NAME --project=nxrm-support-gcp-deployments
```

### Step 2: Check for Filestore Instances

```bash
# List Filestore instances
gcloud filestore instances list --project=nxrm-support-gcp-deployments

# Delete if found
gcloud filestore instances delete INSTANCE_NAME --location=us-central1-a --project=nxrm-support-gcp-deployments
```

### Step 3: Remove Service Connection from Terraform State

```bash
cd /Users/josemiguelromeroespitia/Documents/sonatype/sca-example-terraform/infra-gcp-ha-k8s-helm

# Remove the problematic resource from Terraform state
terraform state rm google_service_networking_connection.private_vpc_connection
```

### Step 4: Delete the VPC Connection Manually

```bash
# This is the nuclear option - only if nothing else works
gcloud services vpc-peerings delete \
  --service=servicenetworking.googleapis.com \
  --network=nexus-iq-ha-vpc \
  --project=nxrm-support-gcp-deployments
```

### Step 5: Run Terraform Destroy Again

```bash
terraform destroy
```

## Understanding the Error

The error occurs because:

1. **Cloud SQL was created** and established a VPC peering connection
2. **Terraform destroy failed** at the GKE cluster creation (permission error)
3. **VPC peering can't be deleted** while Cloud SQL still exists
4. **Cloud SQL isn't in Terraform state** because it was created in a failed apply

## Prevention for Next Time

Before running `terraform apply` again:

1. **Check permissions first**:
   ```bash
   ./check-permissions.sh
   ```

2. **If missing permissions**, get them before deploying:
   - roles/container.admin
   - roles/iam.serviceAccountAdmin
   - roles/iam.securityAdmin

3. **Then deploy**:
   ```bash
   ./tf-apply.sh
   ```

## Quick Status Check

Check what resources currently exist:

```bash
# Terraform state
terraform state list

# Cloud SQL instances
gcloud sql instances list --project=nxrm-support-gcp-deployments

# Filestore instances
gcloud filestore instances list --project=nxrm-support-gcp-deployments

# VPC networks
gcloud compute networks list --project=nxrm-support-gcp-deployments
```
