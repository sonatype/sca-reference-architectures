# Size L settings for infra-azure-ha. deploy.sh, at the top of the repository, lays these
# over terraform.tfvars.example. Only the settings that change with size are here.

container_cpu                    = 15.5   # 15.5 vCPU, leaving 0.5 of the node
container_memory                 = "62Gi" # 62 GB, leaving 2 GB of the node
workload_profile_type            = "D16"  # 16 vCPU, 64 GB per node
iq_min_replicas                  = 2
iq_max_replicas                  = 4
java_opts                        = "-Xms41g -Xmx41g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name                      = "MO_Standard_E8ds_v6" # 8 vCPU, 64 GB
db_storage_mb                    = 262144                # 256 GB, grows automatically
db_storage_tier                  = "P15"
db_high_availability_mode        = "ZoneRedundant"
file_share_quota_gb              = 1536
storage_account_tier             = "Standard"
storage_account_replication_type = "ZRS"

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count       = 3
opensearch_data_instance_type    = "Standard_D4ps_v6"
opensearch_manager_instance_type = "Standard_D2pls_v6"
opensearch_data_disk_gb          = 256

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
