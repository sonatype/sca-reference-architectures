#!/bin/bash

set -e

echo "=============================================="
echo "GCP GKE HA - Force Cleanup Script"
echo "=============================================="
echo ""
echo "This script will:"
echo "1. Find and delete Cloud SQL instances with 'nexus-iq-ha' prefix"
echo "2. Wait for deletion to complete"
echo "3. Run terraform destroy to clean up remaining resources"
echo ""

PROJECT_ID=$(terraform output -raw project_id 2>/dev/null || gcloud config get-value project)

if [ -z "$PROJECT_ID" ]; then
    echo "Error: Could not determine GCP project ID"
    exit 1
fi

echo "Project: $PROJECT_ID"
echo ""

read -p "Do you want to proceed with cleanup? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "Step 1: Finding Cloud SQL instances..."
INSTANCES=$(gcloud sql instances list --project="$PROJECT_ID" --format="value(name)" | grep -E "nexus-iq-ha" || true)

if [ -n "$INSTANCES" ]; then
    echo "Found instances to delete:"
    echo "$INSTANCES"
    echo ""
    
    for INSTANCE in $INSTANCES; do
        echo "Deleting Cloud SQL instance: $INSTANCE"
        gcloud sql instances delete "$INSTANCE" --project="$PROJECT_ID" --quiet || {
            echo "Warning: Failed to delete $INSTANCE (may already be deleting)"
        }
    done
    
    echo ""
    echo "Waiting for Cloud SQL instances to be deleted (this may take 5-10 minutes)..."
    sleep 30
    
    # Wait for all instances to be deleted
    for i in {1..60}; do
        REMAINING=$(gcloud sql instances list --project="$PROJECT_ID" --format="value(name)" | grep -E "nexus-iq-ha" || true)
        if [ -z "$REMAINING" ]; then
            echo "✅ All Cloud SQL instances deleted"
            break
        fi
        echo "Still waiting... ($i/60)"
        sleep 10
    done
else
    echo "No Cloud SQL instances with 'nexus-iq-ha' prefix found"
fi

echo ""
echo "Step 2: Checking for Filestore instances..."
FILESTORE=$(gcloud filestore instances list --project="$PROJECT_ID" --format="value(name)" | grep -E "nexus-iq-ha" || true)

if [ -n "$FILESTORE" ]; then
    echo "Found Filestore instances:"
    echo "$FILESTORE"
    for FS in $FILESTORE; do
        ZONE=$(gcloud filestore instances describe "$FS" --project="$PROJECT_ID" --format="value(location)")
        echo "Deleting Filestore instance: $FS in zone: $ZONE"
        gcloud filestore instances delete "$FS" --location="$ZONE" --project="$PROJECT_ID" --quiet || true
    done
    sleep 10
fi

echo ""
echo "Step 3: Removing Terraform state for problematic resources..."

# Remove the service networking connection from state if it exists
if terraform state list | grep -q "google_service_networking_connection.private_vpc_connection"; then
    echo "Removing service networking connection from state..."
    terraform state rm google_service_networking_connection.private_vpc_connection || true
fi

# Remove any SQL instances from state
for resource in $(terraform state list | grep "google_sql"); do
    echo "Removing $resource from state..."
    terraform state rm "$resource" || true
done

# Remove any Filestore instances from state
for resource in $(terraform state list | grep "google_filestore"); do
    echo "Removing $resource from state..."
    terraform state rm "$resource" || true
done

echo ""
echo "Step 4: Running terraform destroy..."
terraform destroy -auto-approve

echo ""
echo "=============================================="
echo "Cleanup complete!"
echo "=============================================="
echo ""
echo "If you want to deploy again:"
echo "1. Ensure you have the required permissions"
echo "2. Run: ./tf-apply.sh"
