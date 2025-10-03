# Auto-scaling configuration for Container App (equivalent to AWS ECS Auto Scaling)
# Note: Container Apps use KEDA for auto-scaling, which is configured through scale rules

# Container Apps auto-scaling is built into the platform using KEDA
# The scaling behavior is defined through scale rules in the Container App template

# For reference, here are the scaling triggers that are configured in container_app.tf:
# 1. CPU utilization-based scaling (equivalent to AWS ECS CPU target tracking)
# 2. Memory utilization-based scaling (equivalent to AWS ECS Memory target tracking)
# 3. HTTP request-based scaling (unique to Container Apps/KEDA)
# 4. Queue length-based scaling (if using message queues)

# The actual scaling configuration is embedded in the Container App template
# See container_app.tf for the min_replicas, max_replicas, and scale rule configuration