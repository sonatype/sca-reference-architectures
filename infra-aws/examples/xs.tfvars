# Size XS settings for infra-aws. deploy.sh, at the top of the repository, lays these
# over terraform.tfvars.example. Only the settings that change with size are here.

ecs_cpu              = 2048  # 2 vCPU
ecs_memory           = 16384 # 16 GB
iq_desired_count     = 1
java_opts            = "-Xms10g -Xmx10g -XX:MaxDirectMemorySize=3g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=3 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_class    = "db.m8g.large" # 2 vCPU, 8 GB
db_allocated_storage = 64

# One OpenSearch data node, set here because the defaults are the Size M shape
opensearch_instance_type           = "m8g.medium.search"
opensearch_instance_count          = 1
opensearch_volume_size_gb          = 25
opensearch_availability_zone_count = 1
opensearch_index_replicas          = 0

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
