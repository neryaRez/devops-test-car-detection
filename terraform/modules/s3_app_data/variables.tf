variable "name_prefix" {
  type = string
}

variable "bucket_suffix" {
  type = string
  description = "Suffix to keep bucket name globally unique."
}
variable "environment" {
  type = string
  description = "Environment name used for tagging."
  default = "test"
}
