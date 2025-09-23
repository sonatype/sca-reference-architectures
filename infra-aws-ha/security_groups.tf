# Security Group for ECS Tasks
resource "aws_security_group" "ecs_tasks" {
  name_prefix = "${var.cluster_name}-ecs-tasks-sg"
  vpc_id      = aws_vpc.iq_vpc.id

  # HTTP access from ALB
  ingress {
    description     = "HTTP from ALB"
    from_port       = 8070
    to_port         = 8070
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Admin port access from ALB (optional)
  ingress {
    description     = "Admin HTTP from ALB"
    from_port       = 8071
    to_port         = 8071
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Inter-task communication for HA clustering
  ingress {
    description = "Inter-task communication"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-ecs-tasks-sg"
  })
}


# Security Group for Application Load Balancer
resource "aws_security_group" "alb" {
  name_prefix = "${var.cluster_name}-alb-sg"
  vpc_id      = aws_vpc.iq_vpc.id

  # HTTP access from anywhere
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS access from anywhere (if SSL certificate is configured)
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-alb-sg"
  })
}

# Security Group for Aurora Database
resource "aws_security_group" "aurora" {
  name_prefix = "${var.cluster_name}-aurora-sg"
  vpc_id      = aws_vpc.iq_vpc.id

  # PostgreSQL access from ECS tasks
  ingress {
    description     = "PostgreSQL from ECS tasks"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  # Allow Aurora cluster internal communication
  ingress {
    description = "Aurora cluster communication"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-aurora-sg"
  })
}

# Security Group for EFS
resource "aws_security_group" "efs" {
  name_prefix = "${var.cluster_name}-efs-sg"
  vpc_id      = aws_vpc.iq_vpc.id

  # NFS access from ECS tasks
  ingress {
    description     = "NFS from ECS tasks"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-efs-sg"
  })
}

