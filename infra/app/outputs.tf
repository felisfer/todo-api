output "instance_id" {
  value = aws_instance.api.id
}

output "url" {
  description = "Probar con: curl <url>/health"
  value       = "http://${aws_instance.api.public_dns}"
}
