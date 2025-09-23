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

# CloudWatch Log Group for ECS tasks
resource "aws_cloudwatch_log_group" "iq_logs" {
  name              = "/ecs/${var.cluster_name}/nexus-iq-server"
  retention_in_days = var.log_retention_days

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-iq-logs"
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

  container_definitions = jsonencode([
    {
      name         = "nexus-iq-server"
      image        = var.iq_docker_image
      essential    = true
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
          name  = "DB_TYPE"
          value = "postgresql"
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
          name  = "NEXUS_SECURITY_RANDOMPASSWORD"
          value = "false"
        },
        {
          name  = "CLUSTER_DIRECTORY"
          value = "/sonatype-work/clm-cluster"
        }
      ]

      # Override entrypoint to create unique config.yml
      entryPoint = ["/bin/sh"]
      command = [
        "-c",
        <<-EOF
          set -e
          echo "Creating unique sonatypeWork directory for $HOSTNAME"

          # Create directories
          UNIQUE_WORK="/sonatype-work/clm-server-$HOSTNAME"
          mkdir -p "$UNIQUE_WORK"
          mkdir -p "/sonatype-work/clm-cluster"

          # Generate custom config.yml with unique sonatypeWork, PostgreSQL database, and cluster directory
          cat > /etc/nexus-iq-server/config.yml << 'CONFIGEOF'
sonatypeWork: $UNIQUE_WORK
clusterDirectory: /sonatype-work/clm-cluster

# Database configuration for PostgreSQL
database:
  type: postgresql
  hostname: $DB_HOST
  port: $DB_PORT
  name: $DB_NAME
  username: $DB_USER
  password: $DB_PASSWORD

server:
  applicationConnectors:
  - type: http
    port: 8070
  adminConnectors:
  - type: http
    port: 8071
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
    logFormat: "%d{'yyyy-MM-dd HH:mm:ss,SSSZ'} %level [%thread] %X{username} %logger - %msg%n"
  - type: file
    threshold: ALL
    currentLogFilename: "/var/log/nexus-iq-server/clm-server.log"
    archivedLogFilenamePattern: "/var/log/nexus-iq-server/clm-server-%d.log.gz"
    logFormat: "%d{'yyyy-MM-dd HH:mm:ss,SSSZ'} %level [%thread] %X{username} %logger - %msg%n"
    archivedFileCount: 5
createSampleData: true
CONFIGEOF

          # Replace placeholders with actual values
          sed -i "s|\$UNIQUE_WORK|$UNIQUE_WORK|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_HOST|$DB_HOST|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_PORT|$DB_PORT|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_NAME|$DB_NAME|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_USER|$DB_USER|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_PASSWORD|$DB_PASSWORD|g" /etc/nexus-iq-server/config.yml

          echo "Generated config.yml with sonatypeWork: $UNIQUE_WORK"

          # Start IQ Server with default command
          exec java $JAVA_OPTS -jar /opt/sonatype/nexus-iq-server/nexus-iq-server-*.jar server /etc/nexus-iq-server/config.yml
        EOF
      ]

      secrets = [
        {
          name      = "DB_USER"
          valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:username::"
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:password::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.iq_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
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
        }
      ]

      # Resource limits for HA deployment
      memoryReservation = var.ecs_memory_reservation
    }
  ])

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