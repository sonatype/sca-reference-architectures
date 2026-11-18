# Size XL settings for infra-gcp-ha-k8s-helm. deploy.sh, at the top of the repository, lays these
# over terraform.tfvars.example. Only the settings that change with size are here.

node_instance_type             = "n4a-highmem-16" # 16 vCPU, 128 GB (ARM)
node_group_min_size            = 3
node_group_max_size            = 5
node_group_desired_size        = 3
nexus_iq_replica_count         = 3                        # 3 IQ pods at start, the minimum
db_instance_tier               = "db-custom-N4-16-131072" # 16 vCPU, 128 GB, N4 series (Enterprise)
db_disk_provisioned_iops       = 10000
db_disk_provisioned_throughput = 425 # 446 MB/s, given to the API in MiB/s
db_availability_type           = "REGIONAL"
db_disk_size                   = 512 # GB
db_max_disk_size               = 2000
filestore_capacity_gb          = 4096
filestore_max_iops             = 24000

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count       = 3
opensearch_data_instance_type    = "c4a-highmem-8"
opensearch_manager_instance_type = "c4a-standard-2"
opensearch_data_disk_gb          = 250

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
