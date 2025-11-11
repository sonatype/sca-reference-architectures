# Required Permissions for Custom Role "Sonatyper_2024"

## Issue
The deployment requires permissions from `roles/container.admin` and `roles/iam.serviceAccountAdmin`, but your custom role "Sonatyper_2024" currently lacks the necessary GKE container.* permissions.

## Analysis
Your custom role "Sonatyper_2024" already contains:
- ✅ Most `iam.serviceAccount*` permissions (from iam.serviceAccountAdmin)
- ✅ Most `compute.*` permissions
- ✅ Most `cloudsql.*` permissions
- ❌ **ZERO `container.*` permissions for GKE**

## Solution
Instead of assigning the predefined roles `roles/container.admin` and `roles/iam.serviceAccountAdmin`, add the specific missing permissions to your custom role "Sonatyper_2024".

## Permissions to Add to Custom Role

### Critical GKE Permissions (Minimum Required)
These are the essential permissions needed for GKE cluster creation and management:

```
container.clusters.create
container.clusters.delete
container.clusters.get
container.clusters.getCredentials
container.clusters.list
container.clusters.update
container.operations.get
container.operations.list
```

### Service Account Permissions (if missing)
Check if these are already in your custom role. If not, add them:

```
iam.serviceAccounts.create
iam.serviceAccounts.delete
iam.serviceAccounts.get
iam.serviceAccounts.getIamPolicy
iam.serviceAccounts.list
iam.serviceAccounts.setIamPolicy
iam.serviceAccounts.update
```

### Recommended Additional GKE Permissions
For full GKE management capabilities, consider adding these as well:

```
container.clusterRoleBindings.create
container.clusterRoleBindings.delete
container.clusterRoleBindings.get
container.clusterRoleBindings.list
container.clusterRoleBindings.update
container.clusterRoles.bind
container.clusterRoles.create
container.clusterRoles.delete
container.clusterRoles.get
container.clusterRoles.list
container.clusterRoles.update
container.configMaps.create
container.configMaps.delete
container.configMaps.get
container.configMaps.list
container.configMaps.update
container.deployments.create
container.deployments.delete
container.deployments.get
container.deployments.list
container.deployments.update
container.namespaces.create
container.namespaces.delete
container.namespaces.get
container.namespaces.list
container.namespaces.update
container.nodes.get
container.nodes.list
container.persistentVolumeClaims.create
container.persistentVolumeClaims.delete
container.persistentVolumeClaims.get
container.persistentVolumeClaims.list
container.pods.create
container.pods.delete
container.pods.get
container.pods.getLogs
container.pods.list
container.secrets.create
container.secrets.delete
container.secrets.get
container.secrets.list
container.secrets.update
container.serviceAccounts.create
container.serviceAccounts.delete
container.serviceAccounts.get
container.serviceAccounts.list
container.services.create
container.services.delete
container.services.get
container.services.list
container.services.update
container.statefulSets.create
container.statefulSets.delete
container.statefulSets.get
container.statefulSets.list
container.statefulSets.update
```

## How to Update Custom Role

### Option 1: Via Console
1. Go to IAM & Admin > Roles
2. Search for "Sonatyper_2024"
3. Click "Edit Role"
4. Click "Add Permissions"
5. Add the permissions listed above

### Option 2: Via gcloud command
```bash
# Get current role definition
gcloud iam roles describe Sonatyper_2024 --project=nxrm-support-gcp-deployments --format=yaml > sonatyper_2024_role.yaml

# Edit the file to add the new permissions to the includedPermissions list

# Update the role
gcloud iam roles update Sonatyper_2024 --project=nxrm-support-gcp-deployments --file=sonatyper_2024_role.yaml
```

### Option 3: Quick Update (Minimum Permissions Only)
```bash
# Add just the critical GKE permissions
gcloud iam roles update Sonatyper_2024 \
  --project=nxrm-support-gcp-deployments \
  --add-permissions="container.clusters.create,container.clusters.delete,container.clusters.get,container.clusters.getCredentials,container.clusters.list,container.clusters.update,container.operations.get,container.operations.list"
```

## Verification
After updating the role, run the permission check again:
```bash
./check-permissions.sh
```

The script will now pass because your custom role "Sonatyper_2024" will contain the necessary container.* permissions.

## Why This Approach?
- Your organization uses custom roles (Sonatyper_2024)
- The admin cannot see predefined roles in their interface
- Adding specific permissions to your existing custom role is cleaner than assigning multiple predefined roles
- This gives you granular control over exactly what permissions are granted
- You avoid inheriting hundreds of permissions from roles/container.admin that you may not need

## Full roles/container.admin Permissions
If you want to grant the complete set of permissions from `roles/container.admin`, there are 401+ permissions. The list is available but extremely long. The minimum set above should be sufficient for this deployment.
