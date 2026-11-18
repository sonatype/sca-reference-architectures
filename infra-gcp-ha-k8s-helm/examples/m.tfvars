# Size M settings for infra-gcp-ha-k8s-helm. deploy.sh, at the top of the repository, lays these
# over terraform.tfvars.example. Only the settings that change with size are here.

node_instance_type             = "n4a-standard-8" # 8 vCPU, 32 GB (ARM)
node_group_min_size            = 2
node_group_max_size            = 3
node_group_desired_size        = 2
nexus_iq_replica_count         = 2                      # 2 IQ pods at start, the minimum
db_instance_tier               = "db-custom-N4-4-32768" # 4 vCPU, 32 GB, N4 series (Enterprise)
db_disk_provisioned_iops       = 8000
db_disk_provisioned_throughput = 240 # 252 MB/s, given to the API in MiB/s
db_availability_type           = "REGIONAL"
db_disk_size                   = 128 # GB
db_max_disk_size               = 500
filestore_capacity_gb          = 500
filestore_max_iops             = 8000

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count       = 3
opensearch_data_instance_type    = "c4a-standard-2"
opensearch_manager_instance_type = "c4a-standard-1"
opensearch_data_disk_gb          = 100

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
