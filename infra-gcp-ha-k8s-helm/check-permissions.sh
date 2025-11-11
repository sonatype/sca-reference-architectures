#!/bin/bash

set -e

echo "============================================="
echo "GCP GKE HA - Permission Checker"
echo "============================================="

PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
ACCOUNT=$(gcloud config get-value account 2>/dev/null || echo "")

if [ -z "$PROJECT_ID" ]; then
    echo "Error: No GCP project configured"
    echo "Run: gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi

if [ -z "$ACCOUNT" ]; then
    echo "Error: No GCP account authenticated"
    echo "Run: gcloud auth login"
    exit 1
fi

echo ""
echo "Current Configuration:"
echo "  Project: $PROJECT_ID"
echo "  Account: $ACCOUNT"
echo ""

echo "Checking required permissions..."
echo ""

# Required GKE permissions
REQUIRED_CONTAINER_PERMS=(
    "container.clusters.create"
    "container.clusters.delete"
    "container.clusters.get"
    "container.clusters.getCredentials"
    "container.clusters.list"
    "container.clusters.update"
    "container.operations.get"
    "container.operations.list"
)

REQUIRED_IAM_PERMS=(
    "iam.serviceAccounts.create"
    "iam.serviceAccounts.delete"
    "iam.serviceAccounts.get"
    "iam.serviceAccounts.getIamPolicy"
    "iam.serviceAccounts.list"
    "iam.serviceAccounts.setIamPolicy"
    "iam.serviceAccounts.update"
)

MISSING_PERMISSIONS=()

echo "Getting your roles..."
USER_ROLES=$(gcloud projects get-iam-policy "$PROJECT_ID" \
    --flatten="bindings[].members" \
    --filter="bindings.members:$ACCOUNT" \
    --format="value(bindings.role)" | sort -u)

echo "Found roles:"
echo "$USER_ROLES" | sed 's/^/  - /'
echo ""

# Build a cache of all permissions from all roles
echo "Gathering permissions from all your roles..."
ALL_USER_PERMISSIONS=""
for ROLE in $USER_ROLES; do
    echo "  Checking $ROLE..."
    ROLE_PERMS=$(gcloud iam roles describe "$ROLE" --format="value(includedPermissions)" 2>/dev/null || echo "")
    # Convert semicolon-separated to newline-separated
    ROLE_PERMS=$(echo "$ROLE_PERMS" | tr ';' '\n')
    ALL_USER_PERMISSIONS="${ALL_USER_PERMISSIONS}${ROLE_PERMS}"$'\n'
done

echo ""
echo "Checking Container (GKE) Permissions:"
for PERM in "${REQUIRED_CONTAINER_PERMS[@]}"; do
    if echo "$ALL_USER_PERMISSIONS" | grep -q "^${PERM}$"; then
        echo "  ✅ $PERM"
    else
        echo "  ❌ $PERM (MISSING)"
        MISSING_PERMISSIONS+=("$PERM")
    fi
done

echo ""
echo "Checking IAM Service Account Permissions:"
for PERM in "${REQUIRED_IAM_PERMS[@]}"; do
    if echo "$ALL_USER_PERMISSIONS" | grep -q "^${PERM}$"; then
        echo "  ✅ $PERM"
    else
        echo "  ❌ $PERM (MISSING)"
        MISSING_PERMISSIONS+=("$PERM")
    fi
done

if [ ${#MISSING_PERMISSIONS[@]} -gt 0 ]; then
    echo ""
    echo "============================================="
    echo "⚠️  MISSING REQUIRED PERMISSIONS"
    echo "============================================="
    echo ""
    echo "You need the following permissions to deploy GKE:"
    for PERM in "${MISSING_PERMISSIONS[@]}"; do
        echo "  - $PERM"
    done
    echo ""
    echo "How to fix:"
    echo ""
    echo "Ask your admin to add these permissions to your custom role 'Sonatyper_2024':"
    echo ""
    echo "gcloud iam roles update Sonatyper_2024 \\"
    echo "  --project=$PROJECT_ID \\"
    echo "  --add-permissions=\"$(IFS=,; echo "${MISSING_PERMISSIONS[*]}")\""
    echo ""
    echo "Or see PERMISSIONS_NEEDED.md for detailed instructions"
    echo ""
    exit 1
else
    echo ""
    echo "============================================="
    echo "✅ All required permissions present!"
    echo "============================================="
    echo ""
    echo "You can proceed with deployment:"
    echo "  ./tf-plan.sh"
    echo "  ./tf-apply.sh"
fi
