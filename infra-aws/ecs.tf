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

      # Create complete config.yml with database configuration (matching Azure approach)
      entryPoint = ["/bin/sh", "-c"]
      command = [
        <<-EOF
          set -e
          echo "Starting Nexus IQ Server Single Instance with official Docker image"

          # Create comprehensive config.yml with database and logging configuration
          mkdir -p /etc/nexus-iq-server
          cat > /etc/nexus-iq-server/config.yml << 'CONFIGEOF'
sonatypeWork: /sonatype-work

# Database configuration for PostgreSQL
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
    com.sonatype.insight.policy.violation:
      appenders:
      - type: file
        currentLogFilename: "/var/log/nexus-iq-server/policy-violation.log"
        archivedLogFilenamePattern: "/var/log/nexus-iq-server/policy-violation-%d.log.gz"
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
    archivedFileCount: 50

createSampleData: true
CONFIGEOF

          # Replace placeholders with actual environment values
          sed -i "s|\$DB_HOST|$DB_HOST|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_PORT|$DB_PORT|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_NAME|$DB_NAME|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_USERNAME|$DB_USERNAME|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_PASSWORD|$DB_PASSWORD|g" /etc/nexus-iq-server/config.yml

          echo "Successfully created config.yml with database configuration"
          echo "Generated config file contents:"
          cat /etc/nexus-iq-server/config.yml

          # Keep original JAVA_OPTS (no database configuration needed)
          export JAVA_OPTS

          echo "Starting Nexus IQ Server Single Instance"
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
      # Fluent Bit will tail file-based logs and route them to unified log group
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.iq_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "stdout"
        }
      }

      # Enhanced health check matching Kubernetes approach
      # Checks database, cluster directory, and work directory connectivity
      healthCheck = {
        command = [
          "CMD-SHELL",
          "curl -f http://localhost:8071/healthcheck/database && curl -f http://localhost:8071/healthcheck/workDirectory || exit 1"
        ]
        interval    = 30
        timeout     = 10
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
        value = "ref-arch-iq-cluster"
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
        "awslogs-group"         = aws_cloudwatch_log_group.iq_logs.name
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

