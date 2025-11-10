#!/bin/bash

set -e

PROJECT_ID="nxrm-support-gcp-deployments"
CUSTOM_ROLE="Sonatyper_2024"

echo "=========================================="
echo "Adding GKE Permissions to Custom Role"
echo "=========================================="
echo ""
echo "Project: $PROJECT_ID"
echo "Custom Role: $CUSTOM_ROLE"
echo ""

# Check if role exists
if ! gcloud iam roles describe "$CUSTOM_ROLE" --project="$PROJECT_ID" &>/dev/null; then
    echo "❌ Custom role '$CUSTOM_ROLE' not found in project '$PROJECT_ID'"
    exit 1
fi

echo "✅ Custom role found"
echo ""

# Minimum required GKE permissions
PERMISSIONS=(
    "container.clusters.create"
    "container.clusters.delete"
    "container.clusters.get"
    "container.clusters.getCredentials"
    "container.clusters.list"
    "container.clusters.update"
    "container.operations.get"
    "container.operations.list"
)

echo "Adding the following permissions to $CUSTOM_ROLE:"
for PERM in "${PERMISSIONS[@]}"; do
    echo "  - $PERM"
done
echo ""

read -p "Do you want to proceed? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Operation cancelled."
    exit 0
fi

echo ""
echo "Updating custom role..."

# Create comma-separated list
PERM_LIST=$(IFS=,; echo "${PERMISSIONS[*]}")

# Update the role
if gcloud iam roles update "$CUSTOM_ROLE" \
    --project="$PROJECT_ID" \
    --add-permissions="$PERM_LIST" 2>&1 | tee /tmp/role-update.log; then
    
    echo ""
    echo "=========================================="
    echo "✅ Permissions added successfully!"
    echo "=========================================="
    echo ""
    echo "Running permission check..."
    ./check-permissions.sh
else
    echo ""
    echo "❌ Failed to update role"
    echo "See /tmp/role-update.log for details"
    exit 1
fi
