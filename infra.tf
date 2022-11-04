provider "aws" {
    region = var.aws_region
}

resource "aws_vpc" "vpc" {
   cidr_block           = var.vpc_cidr
   enable_dns_hostnames = "true"
   enable_dns_support = "true"
   instance_tenancy = "default"
   tags = {
        Name        = "${var.name_prefix}-vpc"
   }
}

resource "aws_internet_gateway" "igw" {
   vpc_id = aws_vpc.vpc.id
   tags = {
        Name         = "${var.name_prefix}-igw"
        service     = var.name_prefix
   }
}

resource "aws_route_table" "pub-rtb" {
   vpc_id = aws_vpc.vpc.id
   route {
     gateway_id = aws_internet_gateway.igw.id
     cidr_block = "0.0.0.0/0"
   }
   tags = {
     Name        = "${var.name_prefix}-pub-rtb"
     service     = var.name_prefix
   }
}


resource "aws_subnet" "pub-sub" {
  count = "${length(data.aws_availability_zones.available.names)}"
  vpc_id     = aws_vpc.vpc.id
  cidr_block = "${cidrsubnet("${var.vpc_cidr}",3,count.index)}"
  availability_zone = "${element(data.aws_availability_zones.available.names,count.index)}"
  
  tags = {
    Name = "${var.name_prefix}-pub-sb-${count.index+1}"
  }
}

resource "aws_subnet" "app-sub" {
  count = "${length(data.aws_availability_zones.available.names)}"
  vpc_id     = aws_vpc.vpc.id
  cidr_block = "${cidrsubnet("${var.vpc_cidr}",3,"${count.index+3}")}"
  availability_zone = "${element(data.aws_availability_zones.available.names,count.index)}"
  
  tags = {
    Name = "${var.name_prefix}-app-sb-${count.index+1}"
  }
}

resource "aws_subnet" "data-sub" {
  count = "${length(data.aws_availability_zones.available.names)}"
  vpc_id     = aws_vpc.vpc.id
  cidr_block = "${cidrsubnet("${var.cidr_block}",4,"${count.index+12}")}"
  availability_zone = "${element(data.aws_availability_zones.available.names,count.index)}"

  tags = {
    Name = "${var.name_prefix}-data-sb-${count.index+1}"
  }
}

resource "aws_route_table_association" "pub-rtb-ass" {
  count = "${length(data.aws_availability_zones.available.names)}"

  subnet_id      = "${element(aws_subnet.pub-sub.*.id, count.index)}"
  route_table_id = aws_route_table.pub-rtb.id
}


resource "aws_route_table" "data-rtb" {
   vpc_id = "${aws_vpc.vpc.id}"

   tags = {
     name        = "${var.name_prefix}-data-rtb"
   }
}

resource "aws_route_table_association" "data-rtb-ass" {
  count = "${length(data.aws_availability_zones.available.names)}"

  subnet_id      = "${element(aws_subnet.data-sub.*.id, count.index)}"
  route_table_id = aws_route_table.data-rtb.id
}

resource "aws_route_table" "app-rtb" {
   vpc_id = aws_vpc.vpc.id
   count = 3

   tags = {
     Name        = "${var.name_prefix}-app-rtb-${count.index+1}"
   }
}

resource "aws_route_table_association" "app-sub1-rtb-ass" {
  subnet_id      = aws_subnet.app-sub[0].id
  route_table_id = aws_route_table.app-rtb[0].id
}

resource "aws_route_table_association" "app-sub2-rtb-ass" {
  subnet_id      = aws_subnet.app-sub[1].id
  route_table_id = aws_route_table.app-rtb[1].id
}

resource "aws_route_table_association" "app-sub3-rtb-ass" {
  subnet_id      = aws_subnet.app-sub[2].id
  route_table_id = aws_route_table.app-rtb[2].id
}


resource "aws_cloudwatch_log_group" "vpc-flow-log-group" {
  name = "${var.name_prefix}-flow-logs"
  retention_in_days = var.retention
}

resource "aws_flow_log" "flow-log" {
  iam_role_arn    = aws_iam_role.vpc-flow-log-role.arn
  log_destination = aws_cloudwatch_log_group.vpc-flow-log-group.arn
  log_group_name  = aws_cloudwatch_log_group.vpc-flow-log-group.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.vpc.id
}

resource "aws_iam_role" "vpc-flow-log-role" {
  name = "${var.name_prefix}-vpc-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "flow-log-policy" {
  name = "${var.name_prefix}-flow-log-policy"
  role = aws_iam_role.vpc-flow-log-role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_security_group" "endpoint-security-group" {
  name        = "allow_tfc"
  description = "Allow inbound traffic"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description      = "traffic from VPC"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = [aws_vpc.vpc.cidr_block]
 }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "tcp"
    cidr_blocks      = ["127.0.0.1/32"]
  }

  tags = {
    Name = "${var.name_prefix}-endpoint-sg"
  }
}

resource "aws_vpc_endpoint" "ecr-dkr-endpoint" {
  vpc_id            = aws_vpc.vpc.id
  service_name      = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type = "Interface"

  security_group_ids = [
    aws_security_group.endpoint-security-group.id
  ]
  subnet_ids = [
    aws_subnet.app-sub[0].id,
    aws_subnet.app-sub[1].id,
    aws_subnet.app-sub[2].id,
  ]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ecr-api-endpoint" {
  vpc_id            = aws_vpc.vpc.id
  service_name      = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type = "Interface"

  security_group_ids = [
    aws_security_group.endpoint-security-group.id
  ]
  subnet_ids = [
    aws_subnet.app-sub[0].id,
    aws_subnet.app-sub[1].id,
    aws_subnet.app-sub[2].id,
  ]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "secretsmanager-endpoint" {
  vpc_id            = aws_vpc.vpc.id
  service_name      = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type = "Interface"

  security_group_ids = [
    aws_security_group.endpoint-security-group.id
  ]
  subnet_ids = [
    aws_subnet.app-sub[0].id,
    aws_subnet.app-sub[1].id,
    aws_subnet.app-sub[2].id,
  ]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ssm-endpoint" {
  vpc_id            = aws_vpc.vpc.id
  service_name      = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type = "Interface"

  security_group_ids = [
    aws_security_group.endpoint-security-group.id
  ]
  subnet_ids = [
    aws_subnet.app-sub[0].id,
    aws_subnet.app-sub[1].id,
    aws_subnet.app-sub[2].id,
  ]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "cloud-watch-endpoint" {
  vpc_id            = aws_vpc.vpc.id
  service_name      = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type = "Interface"

  security_group_ids = [
    aws_security_group.endpoint-security-group.id
  ]
  subnet_ids = [
    aws_subnet.app-sub[0].id,
    aws_subnet.app-sub[1].id,
    aws_subnet.app-sub[2].id,
  ]
  private_dns_enabled = true
}


resource "aws_vpc_endpoint" "s3-endpoint" {
  vpc_id = aws_vpc.vpc.id
  service_name = "com.amazonaws.${var.aws_region}.s3"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : "*",
        "Action" : [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ],
        "Resource" : "arn:aws:s3:::*"
      }
    ]
  })
  route_table_ids = [
          aws_route_table.app-rtb[0].id,
          aws_route_table.app-rtb[1].id,
          aws_route_table.app-rtb[2].id,
          aws_route_table.data-rtb.id,
  ]
}

resource "aws_vpc_endpoint" "dynamo-endpoint" {
  vpc_id = aws_vpc.vpc.id
  service_name = "com.amazonaws.${var.aws_region}.dynamodb"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : "*",
        "Action" : "dynamodb:*"

# Account need to be added (Ex: arn:aws:dynamodb:${AWS::Region}:${AWS::AccountId}:table/*)
        "Resource" : "arn:aws:dynamodb:${var.aws_region}::table/*"
      }
    ]
  })
  route_table_ids = [
          aws_route_table.app-rtb[0].id,
          aws_route_table.app-rtb[1].id,
          aws_route_table.app-rtb[2].id,
          aws_route_table.data-rtb.id,
  ]
}
