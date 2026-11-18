# Size M settings for infra-azure. deploy.sh, at the top of the repository, lays these
# over terraform.tfvars.example. Only the settings that change with size are here.

container_cpu         = 7.5    # 7.5 vCPU, leaving 0.5 of the node
container_memory      = "30Gi" # 30 GB, leaving 2 GB of the node
workload_profile_type = "D8"   # 8 vCPU, 32 GB per node
java_opts             = "-Xms18g -Xmx18g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name           = "MO_Standard_E4ds_v6" # 4 vCPU, 32 GB
db_storage_mb         = 131072                # 128 GB
file_share_quota      = 500                   # GB

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count       = 3
opensearch_data_instance_type    = "Standard_D2ps_v6"
opensearch_manager_instance_type = "Standard_D2pls_v6"
opensearch_data_disk_gb          = 128

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
