# Size XL settings for infra-aws-ha. deploy.sh, at the top of the repository, lays these
# over terraform.tfvars.example. Only the settings that change with size are here.

ecs_cpu                = 16384  # 16 vCPU
ecs_memory             = 122880 # 120 GB, the maximum at 16 vCPU
ecs_memory_reservation = 90112  # 88 GB soft limit, the 80 GB heap plus 8 GB direct memory
iq_desired_count       = 3      # 3 tasks at start, the minimum
iq_min_count           = 3
iq_max_count           = 5
java_opts              = "-Xms80g -Xmx80g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
aurora_instance_class  = "db.r8g.4xlarge" # 16 vCPU, 128 GB
aurora_instances       = 2                # Multi-AZ with automatic failover

opensearch_instance_type           = "r8g.2xlarge.search"
opensearch_instance_count          = 3
opensearch_volume_size_gb          = 250
opensearch_availability_zone_count = 3
opensearch_dedicated_master_type   = "m8g.large.search"
opensearch_index_replicas          = 1

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
