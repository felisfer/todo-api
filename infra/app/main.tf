# -----------------------------------------------------------------------------
# APP — una EC2 por ambiente (staging / production) que corre el contenedor.
# El mismo código sirve para ambos ambientes; cambia solo la configuración:
#   terraform init -backend-config=staging.s3.tfbackend
#   terraform apply -var-file=staging.tfvars
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # Valores (bucket, key) en *.s3.tfbackend: un estado separado por ambiente.
  backend "s3" {}
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project     = "todo-api"
      App         = "todo-api"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# AMI más reciente de Amazon Linux 2023 (publicada por AWS en SSM Parameter Store)
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# --- Red: solo HTTP de entrada. SIN puerto 22: se administra con SSM ---------

resource "aws_security_group" "api" {
  name        = "todo-api-${var.environment}"
  description = "HTTP publico para todo-api (${var.environment})"

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Salida a internet (descargar imagenes, paquetes)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- Identidad de la EC2: permite que SSM la administre ----------------------

data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "todo-api-ec2-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "todo-api-ec2-${var.environment}"
  role = aws_iam_role.ec2.name
}

# --- La instancia -------------------------------------------------------------

resource "aws_instance" "api" {
  ami                    = data.aws_ssm_parameter.al2023.insecure_value
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.api.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    image = "ghcr.io/${lower(var.github_repo)}:${var.initial_image_tag}"
  })

  metadata_options {
    http_tokens = "required" # IMDSv2 obligatorio (buena práctica de seguridad)
  }

  root_block_device {
    volume_size = 30
    encrypted   = true
  }

  tags = {
    Name = "todo-api-${var.environment}"
  }

  # Las nuevas versiones de la app las despliega scripts/deploy.sh, no Terraform:
  # que un cambio de AMI no reemplace la instancia sin querer.
  lifecycle {
    ignore_changes = [ami, user_data]
  }
}
