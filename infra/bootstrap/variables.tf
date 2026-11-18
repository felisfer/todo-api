variable "region" {
  description = "Región de AWS"
  type        = string
  default     = "us-east-2"
}

variable "github_repo" {
  description = "Repositorio de GitHub con formato owner/nombre (ej. felisfer/todo-api)"
  type        = string
  default     = "felisfer/todo-api"
}

variable "use_github_oidc" {
  description = "true = OIDC + rol (recomendado). false = usuario IAM con llaves, para cuentas cuya SCP bloquea crear proveedores OIDC"
  type        = bool
  default     = false
}
