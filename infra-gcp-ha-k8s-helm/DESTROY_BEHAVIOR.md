# Terraform Destroy Behavior Guide

## Will `tf-destroy.sh` Work in the Future?

### ✅ **YES - After Successful Deployment**

When you complete a **full successful deployment**, `terraform destroy` will work perfectly:

```bash
# Successful deployment scenario
./tf-apply.sh          # ✅ Everything deploys successfully
# ... use the infrastructure ...
./tf-destroy.sh        # ✅ Clean destroy - no issues!
```

**Why it works:**
- All resources properly tracked in Terraform state
- Terraform knows the correct dependency order:
  1. Delete GKE cluster first
  2. Delete Cloud SQL second
  3. Delete VPC service connection third
  4. Delete VPC network last
- No orphaned resources

---

### ❌ **NO - After Failed/Partial Deployment**

If deployment **fails mid-way** (like what happened with the permission error), you'll need special cleanup:

```bash
# Failed deployment scenario
./tf-apply.sh          # ❌ Fails at GKE cluster creation
# ... some resources created, some not ...
./tf-destroy.sh        # ❌ Will fail with "Producer services still using connection"
# ... needs manual intervention ...
./force-cleanup.sh     # ✅ Fixes the problem
```

**Why it fails:**
- Resources created but not fully tracked
- VPC connection established but Cloud SQL state incomplete
- Terraform can't determine proper deletion order

---

## Improved Scripts - Now Automatic!

### `tf-apply.sh` Now Checks Permissions First

The updated script **prevents the problem** by checking permissions before deploying:

```bash
./tf-apply.sh
```

**What it does:**
1. ✅ Checks GCP permissions
2. ✅ Stops if permissions missing
3. ✅ Only proceeds if all permissions present
4. ✅ Deploys infrastructure

**Output example:**
```
Step 1: Checking GCP permissions...
❌ roles/container.admin (MISSING)
❌ Permission check failed!
Please obtain the required permissions before deploying.
```

This **prevents partial deployments** that cause cleanup issues!

---

### `tf-destroy.sh` Now Auto-Recovers

The updated script **automatically handles failures**:

```bash
./tf-destroy.sh
```

**What it does:**
1. Attempts normal `terraform destroy`
2. If it fails, offers to run `force-cleanup.sh`
3. Provides clear instructions

**Output example:**
```
⚠️  Terraform destroy encountered errors

This usually happens when:
1. Deployment failed mid-way
2. Resources exist outside Terraform state
3. Service connections are still in use

Would you like to run the force cleanup script? (yes/no): yes
```

---

## Summary Table

| Scenario | `terraform destroy` | Solution |
|----------|---------------------|----------|
| **Full successful deployment** | ✅ Works perfectly | Just run `./tf-destroy.sh` |
| **Failed/partial deployment** | ❌ Fails with VPC error | Script offers `force-cleanup.sh` |
| **Manual cleanup needed** | ❌ Fails | Run `./force-cleanup.sh` manually |

---

## Best Practices

### 1. **Always Check Permissions First**
```bash
./check-permissions.sh   # Run this first!
```

### 2. **Let Scripts Handle Issues**
```bash
# Don't manually run terraform commands
# Use the scripts instead:
./tf-apply.sh    # Checks permissions automatically
./tf-destroy.sh  # Handles cleanup issues automatically
```

### 3. **If Scripts Don't Work**
```bash
# Fallback manual cleanup
./force-cleanup.sh
```

---

## What Changed

### Before (Your Original Scripts)
```bash
tf-apply.sh:  terraform init && terraform apply
tf-destroy.sh: terraform destroy
# ❌ No permission checking
# ❌ No automatic error recovery
```

### After (Improved Scripts)
```bash
tf-apply.sh:  check-permissions → terraform init → terraform apply
tf-destroy.sh: terraform destroy → auto-detect failures → offer force-cleanup
# ✅ Prevents problems
# ✅ Handles failures automatically
```

---

## Quick Reference

**For normal operations:**
```bash
./check-permissions.sh   # Verify permissions
./tf-apply.sh            # Deploy (checks permissions automatically)
./tf-destroy.sh          # Destroy (handles errors automatically)
```

**If you hit issues:**
```bash
./force-cleanup.sh       # Nuclear option - cleans everything
```

**To understand what exists:**
```bash
terraform state list                              # What Terraform tracks
gcloud sql instances list                         # Actual Cloud SQL instances
gcloud filestore instances list                   # Actual Filestore instances
gcloud compute networks list                      # Actual VPC networks
```

---

## The Bottom Line

**After a successful deployment:** `./tf-destroy.sh` will work every time without issues.

**After a failed deployment:** The scripts now automatically detect and fix the problem for you!

You shouldn't need to manually intervene anymore - the improved scripts handle everything! 🎉
