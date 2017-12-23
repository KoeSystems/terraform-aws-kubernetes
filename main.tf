################################################################################
# Data
################################################################################
data "aws_region" "current" { current = true }
data "aws_availability_zones" "available" {}

################################################################################
# Main DNS domain for K8S cluster
################################################################################
module "k8s_cluster_domain" {
  source      = "github.com/KoeSystems/terraform-aws-route53?ref=v0.1.1"
  domain_name = "${var.cluster_domain}"
}

################################################################################
# VPC for K8S cluster
################################################################################
module "k8s_cluster_vpc" {
  source        = "github.com/KoeSystems/terraform-aws-vpc?ref=v0.4.0"
  name          = "${var.cluster_name}"
  AZs           = "${var.AZs}"
  cidr_block    = "${var.cidr_block}"
  domain_name   = "${module.k8s_cluster_domain.domain_name}"
  domain_ID     = "${module.k8s_cluster_domain.primary_public_zone_id}"
  enable_nat_gw = false  # Force not to create NAT gateway to save money. This makes private network not able to reach Internet
}

################################################################################
# AWS IAM
################################################################################
resource "aws_key_pair" "cluster" {
  key_name     = "${var.cluster_name}" 
  public_key   = "${var.ssh_public_key}"
}