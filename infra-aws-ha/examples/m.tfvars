# Size M settings for infra-aws-ha. deploy.sh, at the top of the repository, lays these
# over terraform.tfvars.example. Only the settings that change with size are here.

ecs_cpu                = 8192  # 8 vCPU
ecs_memory             = 32768 # 32 GB
ecs_memory_reservation = 24576 # 24 GB soft limit, the 20 GB heap plus 4 GB direct memory
iq_desired_count       = 2     # 2 tasks at start, the minimum
iq_min_count           = 2
iq_max_count           = 3
java_opts              = "-Xms20g -Xmx20g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
aurora_instance_class  = "db.r8g.xlarge" # 4 vCPU, 32 GB
aurora_instances       = 2               # Multi-AZ

opensearch_instance_type           = "m8g.large.search"
opensearch_instance_count          = 3
opensearch_volume_size_gb          = 100
opensearch_availability_zone_count = 3
opensearch_index_replicas          = 1

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
