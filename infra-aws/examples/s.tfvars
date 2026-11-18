# Size S settings for infra-aws. deploy.sh, at the top of the repository, lays these
# over terraform.tfvars.example. Only the settings that change with size are here.

ecs_cpu              = 4096  # 4 vCPU
ecs_memory           = 30720 # 30 GB, the maximum at 4 vCPU
iq_desired_count     = 1
java_opts            = "-Xms20g -Xmx20g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=5 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_class    = "db.r8g.large" # 2 vCPU, 16 GB
db_allocated_storage = 128

# One OpenSearch data node, set here because the defaults are the Size M shape
opensearch_instance_type           = "m8g.large.search"
opensearch_instance_count          = 1
opensearch_volume_size_gb          = 50
opensearch_availability_zone_count = 1
opensearch_index_replicas          = 0

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
