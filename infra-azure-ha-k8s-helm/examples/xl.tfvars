# Size XL settings for infra-azure-ha-k8s-helm. deploy.sh, at the top of the repository, lays these
# over terraform.tfvars.example. Only the settings that change with size are here.

node_instance_type               = "Standard_E16ps_v6" # 16 vCPU, 128 GB (ARM)
node_group_min_size              = 3
node_group_max_size              = 5
node_group_desired_size          = 3
nexus_iq_replica_count           = 3                      # 3 IQ pods at start, the minimum
db_sku_name                      = "MO_Standard_E16ds_v6" # 16 vCPU, 128 GB
db_storage_mb                    = 524288                 # 512 GB, grows automatically
db_storage_tier                  = "P20"
db_high_availability_mode        = "ZoneRedundant"
storage_account_tier             = "Premium" # Required for NFS with AKS
storage_share_quota_gb           = 4096
storage_account_replication_type = "ZRS"

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count       = 3
opensearch_data_instance_type    = "Standard_E8ps_v6"
opensearch_manager_instance_type = "Standard_D2ps_v6"
opensearch_data_disk_gb          = 256

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
