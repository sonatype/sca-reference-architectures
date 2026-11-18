# Size M settings for infra-aws. deploy.sh, at the top of the repository, lays these
# over terraform.tfvars.example. Only the settings that change with size are here.

ecs_cpu              = 8192  # 8 vCPU
ecs_memory           = 32768 # 32 GB
iq_desired_count     = 1
java_opts            = "-Xms20g -Xmx20g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_class    = "db.r8g.xlarge" # 4 vCPU, 32 GB
db_allocated_storage = 128             # auto-scales to 500 GB

# The M domain: three data nodes across three zones, which needs a third
# private subnet, and a third public one so the load balancer reaches a task in
# that zone. 10.0.30.0/24 is already db_subnet_cidrs[0].
public_subnet_cidrs                = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnet_cidrs               = ["10.0.10.0/24", "10.0.20.0/24", "10.0.50.0/24"]
opensearch_instance_type           = "m8g.large.search"
opensearch_instance_count          = 3
opensearch_volume_size_gb          = 100
opensearch_availability_zone_count = 3
opensearch_index_replicas          = 1

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
