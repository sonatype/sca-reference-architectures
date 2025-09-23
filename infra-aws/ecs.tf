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
          name  = "DB_TYPE"
          value = "postgresql"
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
        },
        {
          name  = "NEXUS_SECURITY_RANDOMPASSWORD"
          value = "false"
        }
      ]

      # Override entrypoint to create custom config.yml with database configuration
      entryPoint = ["/bin/sh"]
      command = [
        "-c",
        <<-EOF
          set -e
          echo "Generating custom config.yml with PostgreSQL database configuration"

          # Generate custom config.yml with PostgreSQL database configuration
          cat > /etc/nexus-iq-server/config.yml << 'CONFIGEOF'
sonatypeWork: /sonatype-work

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
          sed -i "s|\$DB_HOST|$DB_HOST|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_PORT|$DB_PORT|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_NAME|$DB_NAME|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_USER|$DB_USER|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_PASSWORD|$DB_PASSWORD|g" /etc/nexus-iq-server/config.yml

          echo "Generated config.yml with PostgreSQL database configuration"

          # Start IQ Server with custom config
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

# EFS Access Point for proper permissions
resource "aws_efs_access_point" "iq_access_point" {
  file_system_id = aws_efs_file_system.iq_efs.id

  posix_user {
    uid = 997
    gid = 997
  }

  root_directory {
    path = "/nexus-iq-data"
    creation_info {
      owner_uid   = 997
      owner_gid   = 997
      permissions = "0755"
    }
  }

  tags = {
    Name        = "ref-arch-iq-efs-access-point"
  }
}