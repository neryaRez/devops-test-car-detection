variable "name_prefix" {
  type = string
}
variable "environment" {
  type = string
  description = "Environment name used for tagging."
  default = "prod"
}
