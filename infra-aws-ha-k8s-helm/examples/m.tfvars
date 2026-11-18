# Size M settings for infra-aws-ha-k8s-helm. deploy.sh, at the top of the repository, lays these
# over terraform.tfvars.example. Only the settings that change with size are here.

node_instance_type      = "m8g.2xlarge" # 8 vCPU, 32 GB (ARM)
node_group_desired_size = 2
node_group_min_size     = 2
node_group_max_size     = 3
nexus_iq_replica_count  = 2               # 2 IQ pods at start, the minimum
aurora_instance_class   = "db.r8g.xlarge" # 4 vCPU, 32 GB
aurora_instance_count   = 2

opensearch_instance_type           = "m8g.large.search"
opensearch_instance_count          = 3
opensearch_volume_size_gb          = 100
opensearch_availability_zone_count = 3
opensearch_index_replicas          = 1

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
