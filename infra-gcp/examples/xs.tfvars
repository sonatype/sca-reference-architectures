# Size XS settings for infra-gcp. deploy.sh, at the top of the repository, lays these
# over terraform.tfvars.example. Only the settings that change with size are here.

gce_machine_type      = "n4a-highmem-2" # 2 vCPU, 16 GB (ARM)
java_opts             = "-Xms10g -Xmx10g -XX:MaxDirectMemorySize=3g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=3 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_tier      = "db-custom-2-7680" # 2 vCPU, 7.5 GB
db_disk_type          = "PD_SSD"           # the db-custom-2-* tiers take PD_SSD, not Hyperdisk
db_disk_size          = 64                 # GB
filestore_capacity_gb = 500
filestore_max_iops    = 4000

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count    = 1
opensearch_data_instance_type = "c4a-standard-1"
opensearch_data_disk_gb       = 25

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
