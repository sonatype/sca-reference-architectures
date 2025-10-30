# ECS Cluster for HA deployment
resource "aws_ecs_cluster" "iq_cluster" {
  name = var.cluster_name

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = merge(var.common_tags, {
    Name = var.cluster_name
  })
}

# ECS Task Definition for Nexus IQ Server HA
resource "aws_ecs_task_definition" "iq_task" {
  family                   = "${var.cluster_name}-nexus-iq-server"
  network_mode             = "awsvpc"
  cpu                      = var.ecs_cpu
  memory                   = var.ecs_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn           = aws_iam_role.ecs_task_role.arn
  requires_compatibilities = ["FARGATE"]

  container_definitions = jsonencode(concat([
    {
      name         = "nexus-iq-server"
      image        = var.iq_docker_image
      essential    = true
      user         = "0:0"
      portMappings = [
        {
          containerPort = 8070
          protocol      = "tcp"
          name          = "http"
        },
        {
          containerPort = 8071
          protocol      = "tcp"
          name          = "admin"
        }
      ]

      environment = [
        {
          name  = "JAVA_OPTS"
          value = var.java_opts
        },
        {
          name  = "NEXUS_SECURITY_RANDOMPASSWORD"
          value = "false"
        },
        {
          name  = "DB_HOST"
          value = aws_rds_cluster.iq_aurora_cluster.endpoint
        },
        {
          name  = "DB_PORT"
          value = "5432"
        },
        {
          name  = "DB_NAME"
          value = var.db_name
        },
        {
          name  = "CLUSTER_DIRECTORY"
          value = "/sonatype-work/clm-cluster"
        }
      ]

      # Create HA config with unique work directories and use JAVA_OPTS for database
      entryPoint = ["/bin/sh", "-c"]
      command = [
        <<-EOF
          set -e
          echo "Creating unique sonatypeWork directory for $HOSTNAME"

          # Create unique work directory and shared cluster directory
          UNIQUE_WORK="/sonatype-work/clm-server-$HOSTNAME"
          mkdir -p "$UNIQUE_WORK"
          mkdir -p "/sonatype-work/clm-cluster"

          # Create config.yml with HA settings and database config
          mkdir -p /etc/nexus-iq-server
          cat > /etc/nexus-iq-server/config.yml << 'CONFIGEOF'
sonatypeWork: $UNIQUE_WORK
clusterDirectory: /sonatype-work/clm-cluster

database:
  type: postgresql
  hostname: $DB_HOST
  port: $DB_PORT
  name: $DB_NAME
  username: $DB_USERNAME
  password: $DB_PASSWORD

server:
  applicationConnectors:
  - type: http
    port: 8070
    bindHost: 0.0.0.0
  adminConnectors:
  - type: http
    port: 8071
    bindHost: 0.0.0.0
  requestLog:
    appenders:
    - type: file
      currentLogFilename: "/var/log/nexus-iq-server/request.log"
      archivedLogFilenamePattern: "/var/log/nexus-iq-server/request-%d.log.gz"
      archivedFileCount: 5

logging:
  level: DEBUG
  loggers:
    com.sonatype.insight.scan: INFO
    eu.medsea.mimeutil.MimeUtil2: INFO
    org.apache.http: INFO
    org.apache.http.wire: ERROR
    org.eclipse.birt.report.engine.layout.pdf.font.FontConfigReader: WARN
    org.eclipse.jetty: INFO
    org.apache.shiro.web.filter.authc.BasicHttpAuthenticationFilter: INFO
    com.networknt.schema: OFF
    com.sonatype.insight.audit:
      appenders:
      - type: file
        currentLogFilename: "/var/log/nexus-iq-server/audit.log"
        archivedLogFilenamePattern: "/var/log/nexus-iq-server/audit-%d.log.gz"
        archivedFileCount: 50
  appenders:
  - type: console
    threshold: INFO
    logFormat: "%d{'yyyy-MM-dd HH:mm:ss,SSSZ'} %level [%thread] %X{username} %logger - REPLICA:$HOSTNAME %msg%n"
  - type: file
    threshold: ALL
    currentLogFilename: "/var/log/nexus-iq-server/clm-server.log"
    archivedLogFilenamePattern: "/var/log/nexus-iq-server/clm-server-%d.log.gz"
    logFormat: "%d{'yyyy-MM-dd HH:mm:ss,SSSZ'} %level [%thread] %X{username} %logger - REPLICA:$HOSTNAME %msg%n"
    archivedFileCount: 50

createSampleData: true
CONFIGEOF

          # Replace all placeholders with actual values
          sed -i "s|\$UNIQUE_WORK|$UNIQUE_WORK|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_HOST|$DB_HOST|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_PORT|$DB_PORT|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_NAME|$DB_NAME|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_USERNAME|$DB_USERNAME|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_PASSWORD|$DB_PASSWORD|g" /etc/nexus-iq-server/config.yml

          # Debug: Show what's actually in the config file
          echo "=== DEBUG: Contents of config.yml after ALL replacements ==="
          cat /etc/nexus-iq-server/config.yml
          echo "=== END DEBUG ==="

          # Keep original JAVA_OPTS (no database overrides)
          export JAVA_OPTS

          echo "Starting Nexus IQ Server with sonatypeWork: $UNIQUE_WORK"
          echo "JAVA_OPTS: $JAVA_OPTS"
          exec /opt/sonatype/nexus-iq-server/bin/nexus-iq-server server /etc/nexus-iq-server/config.yml
        EOF
      ]

      secrets = [
        {
          name      = "DB_USERNAME"
          valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:username::"
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:password::"
        }
      ]

      # Container stdout/stderr goes to application log group
      # Fluent Bit will tail file-based logs and route them to appropriate groups
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.iq_logs_application.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "stdout"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8070/ || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 120
      }

      mountPoints = [
        {
          sourceVolume  = "iq-data"
          containerPath = "/sonatype-work"
          readOnly      = false
        },
        {
          sourceVolume  = "iq-logs"
          containerPath = "/var/log/nexus-iq-server"
          readOnly      = false
        }
      ]

      # Resource limits for HA deployment
      memoryReservation = var.ecs_memory_reservation
    }
  ],
  # Fluent Bit sidecar for structured logging
  [{
    name      = "log_router"
    image     = var.fluent_bit_image
    essential = false  # Non-essential: task continues if Fluent Bit fails

    # Write config from environment and run Fluent Bit
    entryPoint = ["/bin/sh", "-c"]
    command = [
      <<-EOF
        set -e
        echo "Loading Fluent Bit configuration from environment"

        # Create config directories
        mkdir -p /fluent-bit/etc /fluent-bit/parsers /fluent-bit/state /var/log/nexus-iq-server/aggregated

        # Write config from environment variable (loaded from SSM via ECS secrets)
        echo "$FLUENT_BIT_CONFIG" > /fluent-bit/etc/fluent-bit.conf
        echo "$FLUENT_BIT_PARSERS" > /fluent-bit/parsers/parsers.conf

        echo "Configuration loaded successfully"
        echo "Starting Fluent Bit..."

        # Run Fluent Bit with fetched configuration
        exec /fluent-bit/bin/fluent-bit -c /fluent-bit/etc/fluent-bit.conf
      EOF
    ]

    # Load configuration from SSM Parameter Store via ECS secrets
    secrets = [
      {
        name      = "FLUENT_BIT_CONFIG"
        valueFrom = aws_ssm_parameter.fluent_bit_config.arn
      },
      {
        name      = "FLUENT_BIT_PARSERS"
        valueFrom = aws_ssm_parameter.fluent_bit_parsers.arn
      }
    ]

    environment = [
      {
        name  = "AWS_REGION"
        value = var.aws_region
      },
      {
        name  = "FLB_LOG_LEVEL"
        value = "info"
      },
      {
        name  = "CLUSTER_NAME"
        value = var.cluster_name
      }
    ]

    # Mount shared log volume (read-write for Fluent Bit to write aggregated logs)
    mountPoints = [
      {
        sourceVolume  = "iq-logs"
        containerPath = "/var/log/nexus-iq-server"
        readOnly      = false  # Fluent Bit needs to write aggregated logs
      }
    ]

    # Resource limits for Fluent Bit sidecar
    cpu            = 256   # 0.25 vCPU
    memory         = 512   # 512 MB
    memoryReservation = 256

    # Health check for Fluent Bit
    healthCheck = {
      command     = ["CMD-SHELL", "curl -sf http://localhost:2020/api/v1/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }

    # Fluent Bit's own logs go to CloudWatch
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.iq_logs_fluent_bit.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "fluent-bit"
      }
    }

    # Start Fluent Bit after IQ Server is running
    dependsOn = [{
      containerName = "nexus-iq-server"
      condition     = "START"
    }]
  }]
  ))

  volume {
    name = "iq-data"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.iq_efs.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.iq_access_point.id
        iam             = "ENABLED"
      }
    }
  }

  volume {
    name = "iq-logs"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.iq_efs.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.iq_logs_access_point.id
        iam             = "ENABLED"
      }
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-iq-task-definition"
  })
}

# ECS Service for High Availability
resource "aws_ecs_service" "iq_service" {
  name            = "${var.cluster_name}-nexus-iq-service"
  cluster         = aws_ecs_cluster.iq_cluster.id
  task_definition = aws_ecs_task_definition.iq_task.arn
  desired_count   = var.iq_desired_count
  launch_type     = "FARGATE"
  platform_version = "LATEST"

  # HA deployment configuration
  deployment_maximum_percent         = 200  # Allow running more than desired during deployment
  deployment_minimum_healthy_percent = 50   # Keep at least 50% running during deployment

  # Deployment circuit breaker
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = aws_subnet.private_subnets[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.iq_tg.arn
    container_name   = "nexus-iq-server"
    container_port   = 8070
  }

  # Service discovery (optional, useful for internal communication)
  service_registries {
    registry_arn = aws_service_discovery_service.iq_service.arn
  }

  # Auto scaling integration
  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [
    aws_lb_listener.iq_listener_http,
    aws_iam_role_policy_attachment.ecs_execution_role_policy,
    aws_iam_role_policy.ecs_task_role_policy
  ]

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-iq-service"
  })
}

# Service Discovery for internal communication between IQ Server instances
resource "aws_service_discovery_private_dns_namespace" "iq_namespace" {
  name        = "${var.cluster_name}.local"
  description = "Private DNS namespace for IQ Server HA"
  vpc         = aws_vpc.iq_vpc.id

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-dns-namespace"
  })
}

resource "aws_service_discovery_service" "iq_service" {
  name = "nexus-iq"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.iq_namespace.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }


  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-service-discovery"
  })
}

# Application Auto Scaling Target
resource "aws_appautoscaling_target" "iq_target" {
  max_capacity       = var.iq_max_count
  min_capacity       = var.iq_min_count
  resource_id        = "service/${aws_ecs_cluster.iq_cluster.name}/${aws_ecs_service.iq_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-autoscaling-target"
  })
}

# Application Auto Scaling Policy (CPU-based)
resource "aws_appautoscaling_policy" "iq_cpu_policy" {
  name               = "${var.cluster_name}-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.iq_target.resource_id
  scalable_dimension = aws_appautoscaling_target.iq_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.iq_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = var.iq_cpu_target_value
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }

  depends_on = [aws_appautoscaling_target.iq_target]
}

# Application Auto Scaling Policy (Memory-based)
resource "aws_appautoscaling_policy" "iq_memory_policy" {
  name               = "${var.cluster_name}-memory-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.iq_target.resource_id
  scalable_dimension = aws_appautoscaling_target.iq_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.iq_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    target_value       = var.iq_memory_target_value
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }

  depends_on = [aws_appautoscaling_target.iq_target]
}
