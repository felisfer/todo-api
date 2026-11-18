variable "region" {
  description = "Región de AWS"
  type        = string
  default     = "us-east-2"
}

variable "environment" {
  description = "Nombre del ambiente"
  type        = string
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment debe ser staging o production."
  }
}

variable "instance_type" {
  description = "Tipo de instancia EC2"
  type        = string
  default     = "t3.micro"
}

variable "github_repo" {
  description = "Repositorio owner/nombre; define la imagen ghcr.io/<repo>"
  type        = string
  default     = "felisfer/todo-api"
}

variable "initial_image_tag" {
  description = "Tag de la imagen con la que arranca la instancia la primera vez"
  type        = string
  default     = "latest"
}
