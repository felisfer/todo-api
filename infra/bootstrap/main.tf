# -----------------------------------------------------------------------------
# BOOTSTRAP — se aplica UNA sola vez por cuenta de AWS (estado local).
# Crea lo que el resto necesita para existir:
#   1. Bucket S3 para el estado remoto de Terraform.
#   2. La identidad con la que GitHub Actions despliega (mínimo privilegio):
#        - use_github_oidc = true  -> proveedor OIDC + rol IAM (lo ideal).
#        - use_github_oidc = false -> usuario IAM con llaves (plan B, por defecto).
#   3. La política de despliegue, igual para cualquiera de las dos.
#   4. Los archivos infra/app/<ambiente>.s3.tfbackend con el bucket de ESTA
#      cuenta, para que nadie tenga que copiar el nombre a mano.
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = "todo-api"
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

# --- 1. Estado remoto --------------------------------------------------------

resource "aws_s3_bucket" "tfstate" {
  # El nombre de un bucket es global en todo AWS: se agrega el ID de la cuenta.
  bucket = "todo-api-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled" # permite recuperar un estado anterior si algo se corrompe
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # el estado puede contener secretos
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- 2. Identidad de GitHub Actions en AWS -----------------------------------
#
# Lo IDEAL es OIDC: GitHub obtiene credenciales TEMPORALES y no se guarda
# ninguna llave. Pero la cuenta de práctica pertenece a una organización de AWS
# cuya Service Control Policy (SCP) bloquea iam:CreateOpenIDConnectProvider:
#
#   ... is not authorized to perform: iam:CreateOpenIDConnectProvider ...
#   with an explicit deny in a service control policy
#
# Un deny explícito de una SCP no se puede anular desde IAM (ni con
# AdministratorAccess). Por eso, por defecto, se usa un usuario IAM con llaves.
# En una cuenta sin esa restricción:  terraform apply -var use_github_oidc=true

# --- 2a. OIDC (use_github_oidc = true) ---------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.use_github_oidc ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_trust" {
  count = var.use_github_oidc ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Solo los jobs de ESTE repositorio que corren en los ambientes
    # staging o production pueden asumir el rol.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repo}:environment:staging",
        "repo:${var.github_repo}:environment:production",
      ]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  count              = var.use_github_oidc ? 1 : 0
  name               = "todo-api-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_trust[0].json
}

# --- 2b. Plan B: usuario IAM (use_github_oidc = false) -----------------------
# La llave de acceso se crea FUERA de Terraform (ver docs/INFRA.md): si se
# creara aquí con aws_iam_access_key, el secreto quedaría en el tfstate.

resource "aws_iam_user" "github_deploy" {
  count = var.use_github_oidc ? 0 : 1
  name  = "todo-api-github-deploy"
}

# --- 3. Política de despliegue ----------------------------------------------
# Mínimo privilegio: solo lo que usa scripts/deploy.sh
data "aws_iam_policy_document" "deploy" {
  statement {
    sid       = "DescribirInstancias"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
  statement {
    sid     = "EjecutarComandoEnInstanciasDeTodoApi"
    actions = ["ssm:SendCommand"]
    resources = [
      "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:instance/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/App"
      values   = ["todo-api"]
    }
  }
  statement {
    sid       = "UsarDocumentoRunShellScript"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ssm:${var.region}::document/AWS-RunShellScript"]
  }
  statement {
    sid       = "LeerResultadoDelComando"
    actions   = ["ssm:GetCommandInvocation", "ssm:ListCommandInvocations"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  count  = var.use_github_oidc ? 1 : 0
  name   = "deploy-todo-api"
  role   = aws_iam_role.github_deploy[0].id
  policy = data.aws_iam_policy_document.deploy.json
}

resource "aws_iam_user_policy" "deploy" {
  count  = var.use_github_oidc ? 0 : 1
  name   = "deploy-todo-api"
  user   = aws_iam_user.github_deploy[0].name
  policy = data.aws_iam_policy_document.deploy.json
}

# --- 4. Configuración del backend para infra/app ------------------------------
# El nombre del bucket depende del ID de la cuenta, así que cambia para cada
# persona. En lugar de copiarlo a mano, se generan los archivos que usa
# "terraform init" en infra/app. Están en .gitignore: cada quien tiene los suyos.

resource "local_file" "backend_config" {
  for_each = toset(["staging", "production"])

  filename = "${path.module}/../app/${each.key}.s3.tfbackend"

  content = join("\n", [
    "# Generado por infra/bootstrap (terraform apply). No editar a mano.",
    "bucket       = \"${aws_s3_bucket.tfstate.bucket}\"",
    "key          = \"app/${each.key}.tfstate\"",
    "region       = \"${var.region}\"",
    "use_lockfile = true",
    "",
  ])
}
