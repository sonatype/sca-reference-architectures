# ECS Cluster
resource "aws_ecs_cluster" "iq_cluster" {
  name = "ref-arch-iq-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name        = "ref-arch-iq-cluster"
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "iq_task" {
  family                   = "ref-arch-nexus-iq-server"
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
        },
        {
          containerPort = 8071
          protocol      = "tcp"
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
          value = aws_db_instance.iq_db.address
        },
        {
          name  = "DB_PORT"
          value = "5432"
        },
        {
          name  = "DB_NAME"
          value = aws_db_instance.iq_db.db_name
        }
      ]

      # Create a basic config file and use JAVA_OPTS to override database settings
      entryPoint = ["/bin/sh", "-c"]
      command = [
        <<-EOF
          set -e

          # Create basic config.yml if it doesn't exist
          if [ ! -f /etc/nexus-iq-server/config.yml ]; then
            mkdir -p /etc/nexus-iq-server
            cat > /etc/nexus-iq-server/config.yml << 'CONFIGEOF'
sonatypeWork: /sonatype-work

server:
  applicationConnectors:
  - type: http
    port: 8070
  adminConnectors:
  - type: http
    port: 8071

logging:
  level: INFO
  appenders:
  - type: console
    threshold: INFO
  - type: file
    threshold: ALL
    currentLogFilename: "/var/log/nexus-iq-server/clm-server.log"
    archivedLogFilenamePattern: "/var/log/nexus-iq-server/clm-server-%d.log.gz"
    archivedFileCount: 5
CONFIGEOF
          fi

          # Start with database configuration via JAVA_OPTS
          JAVA_OPTS="$JAVA_OPTS -Ddw.database.type=postgresql -Ddw.database.hostname=$DB_HOST -Ddw.database.port=$DB_PORT -Ddw.database.name=$DB_NAME -Ddw.database.username=$DB_USERNAME -Ddw.database.password=$DB_PASSWORD"
          export JAVA_OPTS

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
        },
        {
          sourceVolume  = "iq-logs"
          containerPath = "/var/log/nexus-iq-server"
          readOnly      = false
        }
      ]
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

  tags = {
    Name        = "ref-arch-iq-task-definition"
  }
}

# ECS Service
resource "aws_ecs_service" "iq_service" {
  name            = "ref-arch-nexus-iq-service"
  cluster         = aws_ecs_cluster.iq_cluster.id
  task_definition = aws_ecs_task_definition.iq_task.arn
  desired_count   = var.iq_desired_count
  launch_type     = "FARGATE"

  # Deployment configuration for single-instance applications
  deployment_maximum_percent         = 100  # Never run more than desired_count tasks
  deployment_minimum_healthy_percent = 0    # Allow stopping old task before starting new one

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

  depends_on = [
    aws_lb_listener.iq_listener,
    aws_iam_role_policy_attachment.ecs_execution_role_policy
  ]

  tags = {
    Name        = "ref-arch-iq-service"
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "iq_logs" {
  name              = "/ecs/ref-arch-nexus-iq-server"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "ref-arch-iq-logs"
  }
}

# EFS File System for persistent data
resource "aws_efs_file_system" "iq_efs" {
  creation_token = "ref-arch-iq-efs"
  encrypted      = true

  performance_mode = "generalPurpose"
  throughput_mode  = "provisioned"
  provisioned_throughput_in_mibps = 100

  tags = {
    Name        = "ref-arch-iq-efs"
  }
}

# EFS Mount Targets
resource "aws_efs_mount_target" "iq_efs_mt" {
  count           = length(aws_subnet.private_subnets)
  file_system_id  = aws_efs_file_system.iq_efs.id
  subnet_id       = aws_subnet.private_subnets[count.index].id
  security_groups = [aws_security_group.efs.id]
}

# EFS Access Point for data (sonatype-work)
resource "aws_efs_access_point" "iq_access_point" {
  file_system_id = aws_efs_file_system.iq_efs.id

  posix_user {
    uid = 1000
    gid = 1000
  }

  root_directory {
    path = "/nexus-iq-data"
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "0755"
    }
  }

  tags = {
    Name        = "ref-arch-iq-efs-access-point"
  }
}

# EFS Access Point for logs
resource "aws_efs_access_point" "iq_logs_access_point" {
  file_system_id = aws_efs_file_system.iq_efs.id

  posix_user {
    uid = 1000
    gid = 1000
  }

  root_directory {
    path = "/nexus-iq-logs"
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "0755"
    }
  }

  tags = {
    Name        = "ref-arch-iq-efs-logs-access-point"
  }
}

