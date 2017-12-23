variable "cluster_name"   { }
variable "cluster_domain" { }
variable "cidr_block"     { default = "10.0.0.0/16" description = "CIDR block for the VPC where the cluster will be deployed." }
variable "AZs"            { default = "a"           description = "AZs where the cluster will be deployed."}
variable "ssh_public_key" { }


# variable "private_hosted_zone_id"         { }
# variable "ipv6_enabled"                   { default = false }
# variable "masters_count"                  { default = 3 }
variable "master_ebs_optimized"           { default = false }
variable "master_disable_api_termination" { default = false }
variable "master_instance_type"           { default = "t2.micro" }
variable "master_detailed_monitoring"     { default = false }
# variable "master_volume_size"             { default = 20 }
# variable "master_delete_on_termination"   { default = true }