
resource "aws_security_group" "alb" {
  name_prefix = "ref-arch-alb-"
  vpc_id      = aws_vpc.iq_vpc.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Admin interface (testing only)"
    from_port   = 8071
    to_port     = 8071
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "ref-arch-alb-security-group"
  }

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_security_group" "ecs_tasks" {
  name_prefix = "ref-arch-ecs-tasks-"
  vpc_id      = aws_vpc.iq_vpc.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 8070
    to_port         = 8070
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Admin health check from ALB"
    from_port       = 8071
    to_port         = 8071
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "Admin interface public access (testing only)"
    from_port   = 8071
    to_port     = 8071
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "ref-arch-ecs-tasks-security-group"
  }

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_security_group" "rds" {
  name_prefix = "ref-arch-rds-"
  vpc_id      = aws_vpc.iq_vpc.id

  ingress {
    description     = "PostgreSQL from ECS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "ref-arch-rds-security-group"
  }

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_security_group" "efs" {
  name_prefix = "ref-arch-efs-"
  vpc_id      = aws_vpc.iq_vpc.id

  ingress {
    description     = "NFS from ECS"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "ref-arch-efs-security-group"
  }

  lifecycle {
    create_before_destroy = true
  }
}