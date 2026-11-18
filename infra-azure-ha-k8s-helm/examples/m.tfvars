# Size M settings for infra-azure-ha-k8s-helm. deploy.sh, at the top of the repository, lays these
# over terraform.tfvars.example. Only the settings that change with size are here.

node_instance_type        = "Standard_D8ps_v6" # 8 vCPU, 32 GB (ARM)
node_group_min_size       = 2
node_group_max_size       = 3
node_group_desired_size   = 2
nexus_iq_replica_count    = 2                     # 2 IQ pods at start, the minimum
db_sku_name               = "MO_Standard_E4ds_v6" # 4 vCPU, 32 GB
db_storage_mb             = 131072                # 128 GB, grows automatically
db_high_availability_mode = "ZoneRedundant"
storage_share_quota_gb    = 500

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count       = 3
opensearch_data_instance_type    = "Standard_D2ps_v6"
opensearch_manager_instance_type = "Standard_D2pls_v6"
opensearch_data_disk_gb          = 128

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
