terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.2.0"
    }
  } 
}

# Configure the AWS Provider
provider "aws" {
  region     = "us-east-1"
  access_key = ""
  secret_key = ""
}

# Deploy AWS Elastic Cache Endpoint
resource "aws_elasticache_cluster" "cluster" {
  cluster_id           = "redis-cluster"
  engine               = "redis"
  engine_version       = "7.0"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1 
  port                 = 6379
}

# Deploy AWS Open Search 
resource "aws_opensearch_domain" "opensearchdomain" {
  domain_name    = "railssearch"
  engine_version = "Elasticsearch_7.10"

  cluster_config {
    instance_type = "r4.large.search"
  }

  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = true
    master_user_options {
      master_user_name     = "" # Enter master username
      master_user_password = "" # Enter master password
    }
  }

  encrypt_at_rest {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  node_to_node_encryption {
    enabled = true
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 10
  }

  tags = {
    Domain = "opensearchdomain"
  }
}

# Configure VPC

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Configure VPC subnets
resource "aws_subnet" "subnet" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "Main"
  }
}

# Configure ECS Cluster
resource "aws_ecs_cluster" "cluster" {
  name = "railsappcluster"
}

# Creating a target group for the app server
resource "aws_lb_target_group" "tg" {
  name     = "targetgroup"
  port     = 8010
  protocol = "TCP"
  vpc_id   = aws_vpc.main.id
}

# Create ALB for the drkiq application
resource "aws_lb" "lb" {
  name               = "webserverlb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_apptraffic.id]
  subnets            = aws_subnet.subnet.*.id

  enable_deletion_protection = true

  access_logs {
    bucket  = aws_s3_bucket.bucket.id
    prefix  = "test-lb"
    enabled = true
  }

  tags = {
    Environment = "production"
  }
}

# Creating listener for ALB
resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# Task Definition for drkiq service
resource "aws_ecs_task_definition" "drkiq_task_def" {
  family = "drkiq_task"
  container_definitions = jsonencode([
    {
      name      = "drkiq"
      image     = "850267594901.dkr.ecr.us-east-1.amazonaws.com/ECRreponame:imagetag"
      networkMode = "awsvpc"
      operatingSystemFamily = "LINUX"
      requiresCompatibilities = []
      cpu       = 256
      memory    = 512
      essential = true
      portMappings = [
        {
          containerPort = 8010
          hostPort      = 8010
        }
      ],
      "environment" : [
    { "name" : "AWS_ACCESS_KEY_ID", "value" : "" },
    { "name" : "AWS_DEFAULT_REGION", "value" : "us-east-1" },
    { "name" : "AWS_SECRET_ACCESS_KEY", "value" : "" },
    { "name" : "DATABASE_URL", "value" : "" },
    { "name" : "ELASTICSEARCH_PASSWORD", "value" : "" },
    { "name" : "ELASTICSEARCH_URL", "value" : "" },
    { "name" : "ELASTICSEARCH_USERNAME", "value" : "" },
    { "name" : "LISTEN_ON", "value" : "0.0.0.0:8010" },
    { "name" : "REDIS_URL", "value" : "" },
    { "name" : "SECRET_TOKEN", "value" : "Wa4Kdu6hMt3tYKm4jb9p4vZUuc7jBVFw" },
    { "name" : "WORKER_PROCESSES", "value" : "1" }
    ],
    }
  ])

log_configuration {
  log_driver = "awslogs"
  options = { 
    "awslogs-group" = "/ecs/drkiq_task"
    "awslogs-region" = "us-east-1"
    "awslogs-stream-prefix" = "ecs"
    }
  } 
}  

# Create ECS service for drkiq
resource "aws_ecs_service" "drkiqservice" {
  name            = "drkiq"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.drkiq_task_def.arn 
  desired_count   = 1
  
  network_configuration {
    subnets = aws_subnet.subnet.*.id
    security_groups = [aws_security_group.allow_apptraffic.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn 
    container_name   = "drkiq"
    container_port   = 8010
  }
}

# crete S3 bucket resource

resource "aws_s3_bucket" "bucket" {
  bucket = "rails-bucket"

  tags = {
    Name        = "rails_bucket"
  }
}

# create security group for ALB
resource "aws_security_group" "allow_apptraffic" {
  name        = "allow_http"
  description = "Allow HTTP inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description      = "HTTP from VPC"
    from_port        = 0
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "Rule for sidekiq"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "Rule for drkiq"
    from_port        = 0
    to_port          = 8010
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "Rule for postgres"
    from_port        = 0
    to_port          = 5432
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_apptraffic"
  }
}
 
# Autoscaling policy for drkiq
resource "aws_appautoscaling_target" "scalpol_d" {
  max_capacity       = 3
  min_capacity       = 1
  resource_id        = "service/railsappcluster/drkiq"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "scal_dr" {
  name               = "scalpol_drkiq"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.scalpol_d.resource_id
  scalable_dimension = aws_appautoscaling_target.scalpol_d.scalable_dimension
  service_namespace  = aws_appautoscaling_target.scalpol_d.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 60
  }
}

# Create ECS service for sideqik
resource "aws_ecs_service" "sidekiqservice" {
  name            = "sidekiq"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.sideqik_task_def.arn 
  desired_count   = 1
}

# Task Definition for sideqik service
resource "aws_ecs_task_definition" "sideqik_task_def" {
  family = "sideqik_task"
  container_definitions = jsonencode([
    {
      name      = "sidekiq"
      image     = "850267594901.dkr.ecr.us-east-1.amazonaws.com/ECRreponame:imagetagname"
      networkMode = "awsvpc"
      operatingSystemFamily = "LINUX"
      requiresCompatibilities = []
      cpu       = 256
      memory    = 512
      essential = true
      
      "environment" : [
    { "name" : "AWS_ACCESS_KEY_ID", "value" : "" },
    { "name" : "AWS_DEFAULT_REGION", "value" : "" },
    { "name" : "AWS_SECRET_ACCESS_KEY", "value" : "" },
    { "name" : "CACHE_URL", "value" : "" },
    { "name" : "DATABASE_URL", "value" : "" },
    { "name" : "JOB_WORKER_URL", "value" : "" },
    { "name" : "LISTEN_ON", "value" : "0.0.0.0:8010" },
    { "name" : "REDIS_HOST", "value" : "" },
    { "name" : "SECRET_TOKEN", "value" : "Wa4Kdu6hMt3tYKm4jb9p4vZUuc7jBVFw" },
    { "name" : "WORKER_PROCESSES", "value" : "1" }
    ],
    }
  ])
}    

# Autoscaling policy for sidekiq
resource "aws_appautoscaling_target" "scalpol_s" {
  max_capacity       = 3
  min_capacity       = 1
  resource_id        = "service/railsappcluster/sidekiq"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "scal_si" {
  name               = "scalpol_sidekiq"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.scalpol_s.resource_id
  scalable_dimension = aws_appautoscaling_target.scalpol_s.scalable_dimension
  service_namespace  = aws_appautoscaling_target.scalpol_s.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 60
  }
}
# Create ECS service for postgresql
resource "aws_ecs_service" "postgresqlservice" {
  name            = "postgres_service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.postgres_task_def.arn 
  desired_count   = 1
}

# Task Definition for postgres service
resource "aws_ecs_task_definition" "postgres_task_def" {
  family = "postgres_task"
  container_definitions = jsonencode ([
    {
      name      = "postgres"
      image     = "postgres:14.2"
      networkMode = "awsvpc"
      operatingSystemFamily = "LINUX"
      requiresCompatibilities = []
      cpu       = 256
      memory    = 512
      essential = true
      
      "environment" = [
    { "name" : "AWS_ACCESS_KEY_ID", "value" : "AKIA4L57F4CKZHFPZOU4" },
    { "name" : "AWS_DEFAULT_REGION", "value" : "us-east-1" },
    { "name" : "AWS_SECRET_ACCESS_KEY", "value" : "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" },
    { "name" : "CACHE_URL", "value" : "redis://redis-cluster.ouzkgr.0001.use1.cache.amazonaws.com:6379" },
    { "name" : "DATABASE_URL", "value" : "postgresql://drkiq:test_db_password@172.31.59.221:5432/drkiq?encoding=utf8&pool=5&timeout=500" },
    { "name" : "JOB_WORKER_URL", "value" : "redis://redis-cluster.ouzkgr.0001.use1.cache.amazonaws.com:6379" },
    { "name" : "LISTEN_ON", "value" : "0.0.0.0:8010" },
    { "name" : "REDIS_HOST", "value" : "redis://redis-cluster.ouzkgr.0001.use1.cache.amazonaws.com:6379" },
    { "name" : "SECRET_TOKEN", "value" : "Wa4Kdu6hMt3tYKm4jb9p4vZUuc7jBVFw" },
    { "name" : "WORKER_PROCESSES", "value" : "1" }
    ],
    }
  ])
  }  






