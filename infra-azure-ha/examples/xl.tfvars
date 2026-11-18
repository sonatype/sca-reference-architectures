# Size XL settings for infra-azure-ha. deploy.sh, at the top of the repository, lays these
# over terraform.tfvars.example. Only the settings that change with size are here.

container_cpu                    = 15.5    # 15.5 vCPU, leaving 0.5 of the node
container_memory                 = "126Gi" # 126 GB, leaving 2 GB of the node
workload_profile_type            = "E16"   # 16 vCPU, 128 GB per node
iq_min_replicas                  = 3
iq_max_replicas                  = 5
java_opts                        = "-Xms80g -Xmx80g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name                      = "MO_Standard_E16ds_v6" # 16 vCPU, 128 GB
db_storage_mb                    = 524288                 # 512 GB, grows automatically
db_storage_tier                  = "P20"
db_high_availability_mode        = "ZoneRedundant"
file_share_quota_gb              = 4096
storage_account_tier             = "Premium"
storage_account_replication_type = "ZRS"

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count       = 3
opensearch_data_instance_type    = "Standard_E8ps_v6"
opensearch_manager_instance_type = "Standard_D2ps_v6"
opensearch_data_disk_gb          = 256

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
