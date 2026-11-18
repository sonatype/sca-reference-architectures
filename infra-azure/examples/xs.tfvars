# Size XS settings for infra-azure. deploy.sh, at the top of the repository, lays these
# over terraform.tfvars.example. Only the settings that change with size are here.

container_cpu         = 3.5    # 3.5 vCPU, leaving 0.5 of the node
container_memory      = "14Gi" # 14 GB, leaving 2 GB of the node
workload_profile_type = "D4"   # 4 vCPU, 16 GB per node
java_opts             = "-Xms8g -Xmx8g -XX:MaxDirectMemorySize=2g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=3 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name           = "GP_Standard_D2ds_v6" # 2 vCPU, 8 GB
db_storage_mb         = 65536                 # 64 GB

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count    = 1
opensearch_data_instance_type = "Standard_D2pls_v6"
opensearch_data_disk_gb       = 32

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
