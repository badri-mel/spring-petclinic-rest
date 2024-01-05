variable "vpc_cidr" {
  default = "10.100.0.0/16"
}
variable "azs" {
  type = list(string)
  description = "the name of availability zones to use subnets"
  default = [ "us-east-1a", "us-east-1b" ]
}
variable "public_subnets" {
  type = list(string)
  description = "the CIDR blocks to create public subnets"
  default = [ "10.100.10.0/24", "10.100.20.0/24" ]
}
variable "private_subnets" {
  type = list(string)
  description = "the CIDR blocks to create private subnets"
  default = [ "10.100.30.0/24", "10.100.40.0/24" ]
}
variable "cluster_name" {
  type = string
  description = "the name of the ECS cluster"
  default = "spring-petclinic-ecs-cluster"
}


locals {
  aws_region = "us-east-1"
  prefix     = "spring-petclinic-ecs-demo"
  common_tags = {
    Project   = local.prefix
    ManagedBy = "Terraform"
  }
  vpc_cidr = var.vpc_cidr
}

module "ecs_vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name = "${local.prefix}-vpc"
  cidr = local.vpc_cidr
  azs             = var.azs
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets
  enable_nat_gateway     = true
  enable_dns_hostnames   = true
  one_nat_gateway_per_az = true
  tags = local.common_tags
}


resource "aws_ecs_cluster" "spring-petclinic-ecs-cluster" {
  name = "spring-petclinic-ecs-cluster"
}

resource "aws_ecs_service" "spring-petclinic-ecs-service" {
  name            = "spring-petclinic-ecs-service"
  cluster         = aws_ecs_cluster.spring-petclinic-ecs-cluster.id
  task_definition = aws_ecs_task_definition.spring-petclinic-ecs-task-definition.arn
  launch_type     = "FARGATE"
  network_configuration {
    subnets          = module.ecs_vpc.public_subnets
    assign_public_ip = true
  }
  desired_count = 1
}


resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.cluster_name}-ecsTaskExecutionRole"

  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": "sts:AssumeRole",
     "Principal": {
       "Service": "ecs-tasks.amazonaws.com"
     },
     "Effect": "Allow",
     "Sid": ""
   }
 ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecs-task-execution-role-policy-attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecr_repository" "spring-petclinic-repository" {
  name                 = "spring-petclinic-repository"
  image_tag_mutability = "IMMUTABLE"
}

resource "aws_ecr_repository_policy" "spring-petclinic-repository-policy" {
  repository = aws_ecr_repository.spring-petclinic-repository.name
  policy     = <<EOF
  {
    "Version": "2008-10-17",
    "Statement": [
      {
        "Sid": "adds full ecr access to the spring petclinic repository",
        "Effect": "Allow",
        "Principal": "*",
        "Action": [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetLifecyclePolicy",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]
      }
    ]
  }
  EOF
}

resource "aws_cloudwatch_log_group" "spring-petclinic-ecs-container" {
  name              = "/ecs/spring-petclinic-ecs-container"
  retention_in_days = 7
}
# TODO need to add the outbound rule to the security group to allow the traffic to access ECR
resource "aws_ecs_task_definition" "spring-petclinic-ecs-task-definition" {
  family                   = "spring-petclinic-ecs-task-definition"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  memory                   = "1024"
  cpu                      = "512"
  execution_role_arn       = "${aws_iam_role.ecs_task_execution_role.arn}"
  container_definitions    = <<EOF
[
  {
    "name": "spring-petclinic-ecs-container",
    "image": "${aws_ecr_repository.spring-petclinic-repository.repository_url}:3.2.1",
    "memory": 1024,
    "cpu": 512,
    "essential": true,
    "command": [
      "./mvnw",
      "spring-boot:run"
    ],
    "portMappings": [
      {
        "containerPort": 9966,
        "hostPort": 9966
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/spring-petclinic-ecs-container",
        "awslogs-region": "us-east-1",
        "awslogs-stream-prefix": "ecs"
      }
    }
  }
]
EOF
}
#TODO need to add load balancer to access the container
