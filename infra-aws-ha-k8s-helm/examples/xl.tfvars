# Size XL settings for infra-aws-ha-k8s-helm. deploy.sh, at the top of the repository, lays these
# over terraform.tfvars.example. Only the settings that change with size are here.

node_instance_type      = "r9g.4xlarge" # 16 vCPU, 128 GB (ARM)
node_group_desired_size = 3
node_group_min_size     = 3
node_group_max_size     = 5
nexus_iq_replica_count  = 3                # 3 IQ pods at start, the minimum
aurora_instance_class   = "db.r8g.4xlarge" # 16 vCPU, 128 GB
aurora_instance_count   = 2

opensearch_instance_type           = "r8g.2xlarge.search"
opensearch_instance_count          = 3
opensearch_volume_size_gb          = 250
opensearch_availability_zone_count = 3
opensearch_dedicated_master_type   = "m8g.large.search"
opensearch_index_replicas          = 1

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
