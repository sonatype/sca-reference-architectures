# Size L settings for infra-aws-ha. deploy.sh, at the top of the repository, lays these
# over terraform.tfvars.example. Only the settings that change with size are here.

ecs_cpu                = 16384 # 16 vCPU
ecs_memory             = 65536 # 64 GB
ecs_memory_reservation = 51200 # 50 GB soft limit, the 42 GB heap plus 8 GB direct memory
iq_desired_count       = 2     # 2 tasks at start, the minimum
iq_min_count           = 2
iq_max_count           = 4
java_opts              = "-Xms42g -Xmx42g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
aurora_instance_class  = "db.r8g.2xlarge" # 8 vCPU, 64 GB
aurora_instances       = 2                # Multi-AZ with failover

opensearch_instance_type           = "m8g.xlarge.search"
opensearch_instance_count          = 3
opensearch_volume_size_gb          = 150
opensearch_availability_zone_count = 3
opensearch_index_replicas          = 1

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
