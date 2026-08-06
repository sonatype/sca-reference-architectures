
resource "aws_security_group" "ecs_tasks" {
  name_prefix = "${var.cluster_name}-ecs-tasks-sg"
  vpc_id      = aws_vpc.iq_vpc.id


  ingress {
    description     = "HTTP from ALB"
    from_port       = 8070
    to_port         = 8070
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }


  ingress {
    description     = "Admin HTTP from ALB"
    from_port       = 8071
    to_port         = 8071
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }


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



# VPN-only change: the upstream infra-aws-ha reference architecture allows
# ingress from 0.0.0.0/0 on 80/443 here, because its ALB is internet-facing.
# In this variant the ALB is internal (see load_balancer.tf) and only
# reachable from inside the VPC, which itself is only reachable via the
# CloudConnexa VPN connector's routes into the private route tables (see
# cloudconnexa.tf) or from other resources already inside the VPC. Ingress is
# therefore scoped to var.cloudconnexa_client_cidr_blocks instead of the
# public internet.
#
# IMPORTANT: verify what source CIDR CloudConnexa VPN client traffic actually
# presents as by the time it reaches this security group (this depends on
# whether the CloudConnexa connector NATs client traffic to a VPC-internal
# address, or preserves the CloudConnexa client IP pool CIDR configured on
# your CloudConnexa network) and set cloudconnexa_client_cidr_blocks
# accordingly before applying. It defaults to the VPC CIDR, which covers the
# common case where the connector NATs into the VPC.
resource "aws_security_group" "alb" {
  name_prefix = "${var.cluster_name}-alb-sg"
  vpc_id      = aws_vpc.iq_vpc.id


  ingress {
    description = "HTTP from CloudConnexa VPN clients only"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.cloudconnexa_client_cidr_blocks
  }


  ingress {
    description = "HTTPS from CloudConnexa VPN clients only"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.cloudconnexa_client_cidr_blocks
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


resource "aws_security_group" "aurora" {
  name_prefix = "${var.cluster_name}-aurora-sg"
  vpc_id      = aws_vpc.iq_vpc.id


  ingress {
    description     = "PostgreSQL from ECS tasks"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }


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


resource "aws_security_group" "efs" {
  name_prefix = "${var.cluster_name}-efs-sg"
  vpc_id      = aws_vpc.iq_vpc.id


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
