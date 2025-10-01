# 🐳 Docker Image Migration: Community → Official Sonatype Image

## Overview
This PR migrates all Nexus IQ Server deployments from the community Docker image (`sonatypecommunity/nexus-iq-server`) to the official Sonatype image (`sonatype/nexus-iq-server`) across all infrastructure deployments.

## 📋 Changes Summary

### Docker Image Updates (19 files across 4 infrastructure folders)
- **From**: `sonatypecommunity/nexus-iq-server:latest`
- **To**: `sonatype/nexus-iq-server:latest`

### Infrastructure Folders Updated
- ✅ `infra-aws/` - Single instance AWS deployment
- ✅ `infra-aws-ha/` - High availability AWS deployment
- ✅ `infra-azure/` - Single instance Azure deployment
- ✅ `infra-azure-ha/` - High availability Azure deployment

## 🔧 Technical Changes Required

### 1. User Permission Updates (AWS)
The official Docker image uses different user permissions:
- **Changed**: EFS access points from UID/GID `997` → `1000`
- **Files**: `infra-aws/efs.tf`, `infra-aws-ha/efs.tf`

### 2. Configuration Strategy Changes

#### Single Instance Deployments (`infra-aws`, `infra-azure`)
- **Approach**: JAVA_OPTS system properties + basic config.yml
- **Database Config**: Via JAVA_OPTS (supported by official image)
```bash
-Ddw.database.type=postgresql
-Ddw.database.hostname=$DB_HOST
-Ddw.database.port=$DB_PORT
-Ddw.database.name=$DB_NAME
-Ddw.database.username=$DB_USERNAME
-Ddw.database.password=$DB_PASSWORD
```

#### High Availability Deployments (`infra-aws-ha`, `infra-azure-ha`)
- **Approach**: Complete config.yml file (required for unique per-container settings)
- **Reason**: HA clustering requires unique `sonatypeWork` directories per container
- **Implementation**: Shell script with sed replacement for dynamic values

### 3. Startup Command Updates
- **Updated**: Container entrypoint to use proper server command
- **Command**: `server /etc/nexus-iq-server/config.yml`
- **Container User**: Running as root (`0:0`) for config file creation permissions

## 🔍 Key Technical Insights Discovered

### Official vs Community Image Differences
- **User Permissions**: Official image uses UID 1000 (nexus user) vs 997 in community version
- **JAVA_OPTS Limitations**: Official image only supports limited JAVA_OPTS:
  - ✅ Logging configuration (`-Ddw.logging.level=TRACE`)
  - ✅ Standard JVM options (`-Xmx`, `-Xms`)
  - ✅ Java preferences (`-Djava.util.prefs.userRoot=...`)
  - ❌ Clustering settings (`-Ddw.sonatypeWork`, `-Ddw.clusterDirectory`) - **Not supported**

### Configuration Approach by Deployment Type
| Deployment | Configuration Method | Database Config | Clustering |
|------------|---------------------|-----------------|------------|
| Single Instance | JAVA_OPTS + basic config.yml | ✅ JAVA_OPTS | N/A |
| High Availability | Complete config.yml | ✅ config.yml | ✅ Unique work dirs |

## 📁 Files Modified

### Variables & Examples (8 files)
```
infra-aws/variables.tf
infra-aws/terraform.tfvars.example
infra-aws-ha/variables.tf
infra-aws-ha/terraform.tfvars.example
infra-azure/variables.tf
infra-azure/terraform.tfvars.example
infra-azure-ha/variables.tf
infra-azure-ha/terraform.tfvars.example
```

### Infrastructure Configuration (4 files)
```
infra-aws/ecs.tf - Updated container config, EFS permissions
infra-aws-ha/ecs.tf - Major config.yml implementation for HA
infra-azure/container_app.tf - Updated image reference
infra-azure-ha/container_app.tf - HA config.yml implementation
```

### Documentation (7 files)
```
infra-aws/README.md - Updated image reference
infra-aws/ARCHITECTURE.md - Added config approach details
infra-aws-ha/README.md - Updated image reference
infra-aws-ha/ARCHITECTURE.md - Added HA config warnings
infra-azure/README.md - Updated image reference
infra-azure-ha/README.md - Updated image reference
infra-azure-ha/ARCHITECTURE.md - Added HA config warnings
```

## ⚠️ Important Notes

### JAVA_OPTS Usage Guidelines
- **Single Instance**: ✅ Use JAVA_OPTS for database configuration
- **HA Deployment**: ❌ Must use complete config.yml (JAVA_OPTS insufficient for clustering)

### Breaking Changes
- **EFS Access Points**: UID/GID changed from 997 to 1000 (may require infrastructure redeployment)
- **Configuration Files**: HA deployments now require complete config.yml generation

### Backward Compatibility
- All existing functionality preserved
- Database connectivity maintained
- HA clustering behavior unchanged
- Volume mounts and logging remain consistent

## 🧪 Testing Performed
- ✅ **infra-aws**: Successfully deployed with PostgreSQL database connection verified
- ✅ **infra-aws-ha**: Configuration fixes applied and validated
- 📋 **Azure deployments**: Ready for testing (configuration patterns applied)

## 🚀 Deployment Impact
- **Rolling Updates**: ECS/Container Apps will gradually replace containers with new image
- **Downtime**: Minimal during rolling deployment
- **Database**: No changes required (same PostgreSQL connectivity)
- **Data Persistence**: All existing data preserved in EFS/Azure Files

---

This migration ensures compatibility with official Sonatype Docker images while maintaining all existing functionality and providing a foundation for future updates and support.