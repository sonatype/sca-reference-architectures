# Size L settings for infra-gcp-ha. deploy.sh, at the top of the repository, lays these
# over terraform.tfvars.example. Only the settings that change with size are here.

instance_machine_type          = "n4a-standard-16" # 16 vCPU, 64 GB (ARM)
iq_target_instances            = 2                 # 2 instances at start, the minimum
iq_min_instances               = 2
iq_max_instances               = 4
java_opts                      = "-Xms42g -Xmx42g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_tier               = "db-custom-N4-8-65536" # 8 vCPU, 64 GB, N4 series (Enterprise)
db_disk_provisioned_iops       = 8000
db_disk_provisioned_throughput = 340 # 357 MB/s, given to the API in MiB/s
db_availability_type           = "REGIONAL"
db_disk_size                   = 256 # GB
db_max_disk_size               = 1000
filestore_capacity_gb          = 1536
filestore_max_iops             = 16000

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count       = 3
opensearch_data_instance_type    = "c4a-standard-4"
opensearch_manager_instance_type = "c4a-standard-1"
opensearch_data_disk_gb          = 150

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
