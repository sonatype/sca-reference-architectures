#!/bin/bash

set -e

echo "=============================================="
echo "GCP GKE HA - Force Cleanup Script"
echo "=============================================="
echo ""
echo "This script will:"
echo "1. Find and delete Cloud SQL instances belonging to this deployment"
echo "2. Wait for deletion to complete"
echo "3. Run terraform destroy to clean up remaining resources"
echo ""

PROJECT_ID=$(terraform output -raw project_id 2>/dev/null || gcloud config get-value project)

# Match on this deployment's own cluster_name, not a fixed prefix. Several sizes of this
# architecture can share one project, and a fixed prefix would match all of them.
CLUSTER_NAME=$(terraform output -raw gke_cluster_name 2>/dev/null || echo "")
CLUSTER_NAME_SOURCE="terraform output"

# terraform output needs usable state, and an unusable state is the case this script exists for, so
# fall back to the value the deployment was applied with. The sed takes the first double-quoted
# value on the cluster_name line and ignores anything after it, so a trailing comment such as
# `cluster_name = "iq-m"  # size M` still reads as iq-m.
if [ -z "$CLUSTER_NAME" ] && [ -f terraform.tfvars ]; then
    CLUSTER_NAME=$(sed -n 's/^[[:space:]]*cluster_name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' terraform.tfvars | head -1)
    CLUSTER_NAME_SOURCE="terraform.tfvars"
fi

# Neither source named one, so the deployment ran on the variable's own default.
if [ -z "$CLUSTER_NAME" ]; then
    CLUSTER_NAME="nexus-iq-ha"
    CLUSTER_NAME_SOURCE="the cluster_name default"
fi

if [ -z "$PROJECT_ID" ]; then
    echo "Error: Could not determine GCP project ID"
    exit 1
fi

echo "Project: $PROJECT_ID"
echo "Cluster: $CLUSTER_NAME (read from $CLUSTER_NAME_SOURCE)"
echo ""
echo "Check that name before answering. Everything matching it is deleted without a further"
echo "prompt, and a project can hold several sizes of this architecture."
echo ""

read -p "Do you want to proceed with cleanup? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "Step 1: Finding Cloud SQL instances..."
# Anchored on the whole instance name, which database.tf builds as
# "<cluster_name>-db-<8 lowercase alphanumerics>" and "<cluster_name>-db-replica-<same>". A bare
# "^$CLUSTER_NAME-db" prefix also matches another deployment whose own cluster_name starts with
# "$CLUSTER_NAME-db", and the delete below passes --quiet. cluster_name is validated to lowercase
# letters, numbers and hyphens, so it carries no regular expression metacharacter.
SQL_NAME_PATTERN="^$CLUSTER_NAME-db(-replica)?-[a-z0-9]{8}$"
INSTANCES=$(gcloud sql instances list --project="$PROJECT_ID" --format="value(name)" | grep -E "$SQL_NAME_PATTERN" || true)

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
        REMAINING=$(gcloud sql instances list --project="$PROJECT_ID" --format="value(name)" | grep -E "$SQL_NAME_PATTERN" || true)
        if [ -z "$REMAINING" ]; then
            echo "✅ All Cloud SQL instances deleted"
            break
        fi
        echo "Still waiting... ($i/60)"
        sleep 10
    done
else
    echo "No Cloud SQL instances found for $CLUSTER_NAME"
fi

echo ""
echo "Step 2: Checking for Filestore instances..."
# Anchored on the whole instance name, which storage.tf builds as
# "<cluster_name>-filestore-<8 lowercase alphanumerics>", because the delete below passes
# --quiet. The Filestore API returns `name` as the full resource path, so the match allows the
# "projects/.../instances/" part in front of it.
FILESTORE_NAME_PATTERN="(^|/)$CLUSTER_NAME-filestore-[a-z0-9]{8}$"
FILESTORE=$(gcloud filestore instances list --project="$PROJECT_ID" --format="value(name)" | grep -E "$FILESTORE_NAME_PATTERN" || true)

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
