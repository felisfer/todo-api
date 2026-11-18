output "state_bucket" {
  description = "Bucket del estado remoto (ya quedó escrito en infra/app/*.s3.tfbackend)"
  value       = aws_s3_bucket.tfstate.bucket
}

output "github_deploy_role_arn" {
  description = "(Solo con use_github_oidc=true) Poner en GitHub > Settings > Variables > AWS_ROLE_ARN"
  value       = one(aws_iam_role.github_deploy[*].arn)
}

output "github_deploy_user" {
  description = "(Solo con use_github_oidc=false) Crear su llave: aws iam create-access-key --user-name <este valor>"
  value       = one(aws_iam_user.github_deploy[*].name)
}
