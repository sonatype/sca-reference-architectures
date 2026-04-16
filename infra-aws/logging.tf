




resource "aws_cloudwatch_log_group" "iq_logs" {
  name              = "/ecs/${var.cluster_name}/nexus-iq-server"
  retention_in_days = var.log_retention_days

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-iq-logs"
    Description = "Unified log group for all Nexus IQ Server logs"
  })
}


resource "aws_s3_bucket" "log_archive" {
  count  = var.enable_log_archive ? 1 : 0
  bucket = "${var.cluster_name}-iq-logs-archive-${data.aws_caller_identity.current.account_id}"

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-iq-logs-archive"
    Description = "Long-term archive for IQ Server logs"
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "log_archive" {
  count  = var.enable_log_archive ? 1 : 0
  bucket = aws_s3_bucket.log_archive[0].id

  rule {
    id     = "archive-old-logs"
    status = "Enabled"

    filter {
      prefix = "nexus-iq-logs/"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }

    expiration {
      days = var.log_archive_retention_days
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "log_archive" {
  count  = var.enable_log_archive ? 1 : 0
  bucket = aws_s3_bucket.log_archive[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}


resource "aws_ssm_parameter" "fluent_bit_config" {
  name        = "/ecs/${var.cluster_name}/nexus-iq-server/fluent-bit-config"
  description = "Fluent Bit configuration for Nexus IQ Server log parsing"
  type        = "String"
  tier        = "Advanced"
  value       = <<-EOF
[SERVICE]
    Flush         5
    Grace         30
    Log_Level     info
    Parsers_File  /fluent-bit/parsers/parsers.conf
    HTTP_Server   On
    HTTP_Listen   0.0.0.0
    HTTP_Port     2020


[INPUT]
    Name              tail
    Path              /var/log/nexus-iq-server/clm-server.log
    Tag               iq.application
    Read_from_Head    true
    Refresh_Interval  10
    Skip_Long_Lines   On
    DB                /fluent-bit/state/clm-server.db


[INPUT]
    Name              tail
    Path              /var/log/nexus-iq-server/request.log
    Tag               iq.request
    Parser            iq_request
    Read_from_Head    true
    Refresh_Interval  10
    DB                /fluent-bit/state/request.db


[INPUT]
    Name              tail
    Path              /var/log/nexus-iq-server/audit.log
    Tag               iq.audit
    Parser            json
    Read_from_Head    true
    Refresh_Interval  10
    DB                /fluent-bit/state/audit.db


[INPUT]
    Name              tail
    Path              /var/log/nexus-iq-server/policy-violation.log
    Tag               iq.policy_violation
    Parser            json
    Read_from_Head    true
    Refresh_Interval  10
    DB                /fluent-bit/state/policy-violation.db


[INPUT]
    Name              tail
    Path              /var/log/nexus-iq-server/stderr.log
    Tag               iq.stderr
    Read_from_Head    true
    Refresh_Interval  10
    DB                /fluent-bit/state/stderr.db
    Skip_Long_Lines   Off
    Buffer_Max_Size   256k


[FILTER]
    Name                record_modifier
    Match               iq.*
    Record              ecs_cluster ${var.cluster_name}
    Record              ecs_task_family ${var.cluster_name}-nexus-iq-server
    Record              aws_region ${var.aws_region}


[FILTER]
    Name                modify
    Match               iq.*
    Add                 hostname $${HOSTNAME}

[OUTPUT]
    Name                cloudwatch_logs
    Match               iq.application
    region              ${var.aws_region}
    log_group_name      /ecs/${var.cluster_name}/nexus-iq-server
    log_stream_prefix   application/
    auto_create_group   false

[OUTPUT]
    Name                cloudwatch_logs
    Match               iq.request
    region              ${var.aws_region}
    log_group_name      /ecs/${var.cluster_name}/nexus-iq-server
    log_stream_prefix   request/
    auto_create_group   false

[OUTPUT]
    Name                cloudwatch_logs
    Match               iq.audit
    region              ${var.aws_region}
    log_group_name      /ecs/${var.cluster_name}/nexus-iq-server
    log_stream_prefix   audit/
    auto_create_group   false

[OUTPUT]
    Name                cloudwatch_logs
    Match               iq.policy_violation
    region              ${var.aws_region}
    log_group_name      /ecs/${var.cluster_name}/nexus-iq-server
    log_stream_prefix   policy-violation/
    auto_create_group   false

[OUTPUT]
    Name                cloudwatch_logs
    Match               iq.stderr
    region              ${var.aws_region}
    log_group_name      /ecs/${var.cluster_name}/nexus-iq-server
    log_stream_prefix   stderr/
    auto_create_group   false
    retry_limit         2


[OUTPUT]
    Name                file
    Match               iq.application
    Path                /var/log/nexus-iq-server/aggregated/application
    Format              plain
    mkdir               true


[OUTPUT]
    Name                file
    Match               iq.request
    Path                /var/log/nexus-iq-server/aggregated/request
    Format              plain
    mkdir               true


[OUTPUT]
    Name                file
    Match               iq.audit
    Path                /var/log/nexus-iq-server/aggregated/audit
    Format              plain
    mkdir               true


[OUTPUT]
    Name                file
    Match               iq.policy_violation
    Path                /var/log/nexus-iq-server/aggregated/policy-violation
    Format              plain
    mkdir               true


[OUTPUT]
    Name                file
    Match               iq.stderr
    Path                /var/log/nexus-iq-server/aggregated/stderr
    Format              plain
    mkdir               true

${var.enable_log_archive ? <<-S3_OUTPUT

[OUTPUT]
    Name                s3
    Match               iq.*
    region              ${var.aws_region}
    bucket              ${var.cluster_name}-iq-logs-archive-${data.aws_caller_identity.current.account_id}
    total_file_size     100M
    s3_key_format       /nexus-iq-logs/year=%Y/month=%m/day=%d/hour=%H/$${TAG}-%H%M%S
    s3_key_format_tag_delimiters .-
    store_dir           /fluent-bit/s3-buffer
S3_OUTPUT
: ""}
EOF

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-fluent-bit-config"
  })
}


resource "aws_ssm_parameter" "fluent_bit_parsers" {
  name        = "/ecs/${var.cluster_name}/nexus-iq-server/fluent-bit-parsers"
  description = "Custom parsers for Nexus IQ Server logs"
  type        = "String"
  tier        = "Advanced"
  value       = <<-EOF
[PARSER]
    Name         iq_request
    Format       regex
    Regex        ^(?<client_host>[^ ]*) (?<ident>[^ ]*) (?<auth_user>[^ ]*) \[(?<time>[^\]]*)\] "(?<method>[^ ]*) (?<path>[^ ]*) (?<protocol>[^"]*)" (?<status>[^ ]*) (?<bytes>[^ ]*) (?<elapsed_time>[^ ]*) "(?<user_agent>[^"]*)"$
    Time_Key     time
    Time_Format  %d/%b/%Y:%H:%M:%S %z
    Types        status:integer bytes:integer elapsed_time:integer

[PARSER]
    Name         iq_application
    Format       regex
    Regex        ^(?<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d{3}[+-]\d{4}) (?<level>[^ ]*) \[(?<thread>[^\]]*)\] (?<username>[^ ]*) (?<logger>[^ ]*) - (?<message>.*)$
    Time_Key     timestamp
    Time_Format  %Y-%m-%d %H:%M:%S,%L%z

[PARSER]
    Name   json
    Format json
    Time_Key time
    Time_Format %Y-%m-%dT%H:%M:%S.%L%z
EOF

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-fluent-bit-parsers"
  })
}
