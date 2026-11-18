# Size M settings for infra-gcp. deploy.sh, at the top of the repository, lays these
# over terraform.tfvars.example. Only the settings that change with size are here.

gce_machine_type               = "n4a-standard-8" # 8 vCPU, 32 GB (ARM)
java_opts                      = "-Xms20g -Xmx20g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_tier               = "db-custom-N4-4-32768" # 4 vCPU, 32 GB, N4 series (Enterprise)
db_disk_type                   = "HYPERDISK_BALANCED"   # the only storage the N4 tiers take
db_disk_provisioned_iops       = 8000                   # read and write combined
db_disk_provisioned_throughput = 240                    # 252 MB/s, given to the API in MiB/s
db_disk_size                   = 128                    # GB, auto-resize enabled
filestore_capacity_gb          = 500
filestore_max_iops             = 8000

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count       = 3
opensearch_data_instance_type    = "c4a-standard-2"
opensearch_manager_instance_type = "c4a-standard-1"
opensearch_data_disk_gb          = 100

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
