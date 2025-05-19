variable "civo_token" {}

variable "region" {
  type        = string
  default     = "LON1" # or "DG-EXM" or "NYC1"
  description = "The region to provision the cluster against"
}

variable "node_size" {
  type        = string
  default     = "an.g1.h100.x1" # or an.g1.l40s.x1 or g4g.40.small
  description = "The size of the nodes to provision. Run `civo size list` for all options"
}

variable "name_prefix" {
  description = "Prefix to append to the name of the cluster being created"
  type        = string
  default     = "ollama"
}

