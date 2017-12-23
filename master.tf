################################################################################
# Data
################################################################################
data "aws_ami_ids" "master" {
  owners = ["self"]

  filter {
    name   = "name"
    values = ["k8s-master-*"]
  } 
}

data "template_file" "master-user-data" {
  template = "${file("${path.module}/userdata/master.tpl")}"
  count    = "${module.k8s_cluster_vpc.AZs_number}"

  vars {
    hostname = "master00${count.index+1}"
    fqdn     = "master00${count.index+1}.${var.cluster_name}.${data.aws_region.current.name}.${var.cluster_domain}"
  }
}

################################################################################
# AWS IAM
################################################################################
resource "aws_iam_role" "master" {
  name               = "${var.cluster_name}-master"
  path               = "/${var.cluster_name}/"
  assume_role_policy = "${file("${path.module}/policies/instance_profile_master.json")}"
}

resource "aws_iam_instance_profile" "master" {
  name = "${var.cluster_name}-master"
  path = "/${var.cluster_name}/"
  role = "${aws_iam_role.master.name}"
}

resource "aws_iam_policy" "master" {
  name        = "${var.cluster_name}-master"
  path        = "/${var.cluster_name}/"
  description = "${var.cluster_name} master policy for K8s cluster."
  policy      = "${file("${path.module}/policies/policy_master.json")}"
}

resource "aws_iam_policy_attachment" "master" {
  name       = "test-attachment"
  roles      = ["${aws_iam_role.master.name}"]
  policy_arn = "${aws_iam_policy.master.arn}"
}

################################################################################
# AWS EC2 Security Group
################################################################################
resource "aws_security_group" "master" {
  name        = "${var.cluster_name}-master"
  description = "${var.cluster_name}-master"
  vpc_id      = "${module.k8s_cluster_vpc.vpc_id}"

  tags {
    Name      = "${var.cluster_name}-master"
  }
}

resource "aws_security_group_rule" "allow_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [ "${module.k8s_cluster_vpc.ipv4_cidr_block}" ]
  security_group_id = "${aws_security_group.master.id}"
}

resource "aws_security_group_rule" "allow_etcd_server" {
  type              = "ingress"
  from_port         = 2380
  to_port           = 2380
  protocol          = "tcp"
  self              = true
  security_group_id = "${aws_security_group.master.id}"
}

resource "aws_security_group_rule" "allow_etcd_client" {
  type              = "ingress"
  from_port         = 2379
  to_port           = 2379
  protocol          = "tcp"
  self              = true
  security_group_id = "${aws_security_group.master.id}"
}

resource "aws_security_group_rule" "allow_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = [ "0.0.0.0/0" ]
  security_group_id = "${aws_security_group.master.id}"
}

################################################################################
# AWS EC2 Instances
################################################################################
resource "aws_instance" "master" {
  ami                         = "${data.aws_ami_ids.master.ids[0]}"
  ebs_optimized               = "${var.master_ebs_optimized}"
  disable_api_termination     = "${var.master_disable_api_termination}"
  instance_type               = "${var.master_instance_type}"
  key_name                    = "${aws_key_pair.cluster.key_name}"
  monitoring                  = "${var.master_detailed_monitoring}"
  vpc_security_group_ids      = [ "${aws_security_group.master.id}" ]
  subnet_id                   = "${element(split(",", module.k8s_cluster_vpc.subnets_private_ids), count.index)}"
  associate_public_ip_address = false
  private_ip                  = "${cidrhost(element(split(",", module.k8s_cluster_vpc.subnets_private_cidr_block), count.index), 10)}"
  source_dest_check           = false
  user_data                   = "${element(data.template_file.master-user-data.*.rendered, count.index)}"
  iam_instance_profile        = "${aws_iam_instance_profile.master.id}"
  #ipv6_address_count          = "${var.ipv6_enabled ? 1 : 0}"
  root_block_device {
    volume_type               = "gp2"
    volume_size               = "20"
    delete_on_termination     = true
  }

  # lifecycle {
  #   ignore_changes = [ "tags.Name", "tags.%" ]
  # }

  tags {
    Name              = "master00${count.index+1}"
    KubernetesCluster = "${var.cluster_name}.${data.aws_region.current.name}.${var.cluster_domain}"
  }

  count = "${module.k8s_cluster_vpc.AZs_number}"
}

################################################################################
# AWS EC2 EBS Volumes
################################################################################
resource "aws_ebs_volume" "etcd_master_data" {
  availability_zone = "${data.aws_region.current.name}${element(split(",",var.AZs), count.index)}"
  #encrypted         = true
  size              = 10
  type              = "gp2"

  tags {
    Name              = "master00${count.index+1}-etcd"
    KubernetesCluster = "${var.cluster_name}.${data.aws_region.current.name}.${var.cluster_domain}"
  }
  
  count = "${module.k8s_cluster_vpc.AZs_number}"
}

resource "aws_volume_attachment" "etcd_master" {
  device_name = "/dev/sdf"
  volume_id   = "${element(aws_ebs_volume.etcd_master_data.*.id, count.index)}"
  instance_id = "${element(aws_instance.master.*.id, count.index)}"
  count       = "${module.k8s_cluster_vpc.AZs_number}"
}


# ################################################################################
# # AWS ELB
# ################################################################################
# # resource "aws_security_group" "elb_master" {
# #   name        = "allow_all"
# #   description = "Allow all inbound traffic"
# # }

# # resource "aws_security_group_rule" "allow_all" {
# #   type            = "ingress"
# #   from_port       = 0
# #   to_port         = 65535
# #   protocol        = "tcp"
# #   cidr_blocks     = ["0.0.0.0/0"]
# #   prefix_list_ids = ["pl-12c4e678"]
# #   security_group_id = "sg-123456"
# # }

# # resource "aws_elb" "master" {
# #   name                        = "${var.cluster_name}-master"
# #   internal                    = true
# #   availability_zones          = [ "${sort(data.aws_availability_zones.available.names)}" ]
# #   security_groups             = [ "${aws_security_group.elb_master.id}" ]
# #   subnets                     = [ "${data.aws_subnet_ids.master_private.ids}" ]
# #   cross_zone_load_balancing   = true
# #   idle_timeout                = 300
# #   connection_draining         = true
# #   connection_draining_timeout = 300

# #   # access_logs {
# #   #   bucket        = "foo"
# #   #   bucket_prefix = "bar"
# #   #   interval      = 60
# #   # }

# #   listener {
# #     instance_port      = 443
# #     instance_protocol  = "https"
# #     lb_port            = 80
# #     lb_protocol        = "http"
# #     #ssl_certificate_id = "arn:aws:iam::123456789012:server-certificate/certName"
# #   }

# #   health_check {
# #     healthy_threshold   = 2
# #     unhealthy_threshold = 2
# #     timeout             = 3
# #     target              = "HTTP:8080/"
# #     interval            = 30
# #   }

# #   # instances                   = ["${aws_instance.foo.id}"]

# #   # tags {
# #   #   Name = "foobar-terraform-elb"
# #   # }
# # }

# # resource "aws_elb_attachment" "master" {
# #   elb      = "${aws_elb.master.id}"
# #   instance = "${element(aws_instance.master.*.id, count.index)}"
# #   count    = "${var.masters_count}"
# # }

################################################################################
# DNS entries
################################################################################
resource "aws_route53_record" "master" {
  zone_id = "${module.k8s_cluster_vpc.secondary_private_zone_id}"
  name    = "master00${count.index+1}"
  type    = "A"
  ttl     = "60"
  records = [ "${element(aws_instance.master.*.private_ip, count.index)}" ] 
  count   = "${module.k8s_cluster_vpc.AZs_number}"
}

resource "aws_route53_record" "etcd_server_srv" {
  zone_id = "${module.k8s_cluster_vpc.secondary_private_zone_id}"
  #name    = "_etcd-server-ssl._tcp"
  name    = "_etcd-server._tcp"
  type    = "SRV"
  ttl     = "60"
  records = [ "${formatlist("0 0 2380 %s.%s.%s.%s",aws_route53_record.master.*.name, var.cluster_name, data.aws_region.current.name, var.cluster_domain )}" ]
}

resource "aws_route53_record" "etcd_client_srv" {
  zone_id = "${module.k8s_cluster_vpc.secondary_private_zone_id}"
  #name    = "_etcd-client-ssl._tcp"
  name    = "_etcd-client._tcp"
  type    = "SRV"
  ttl     = "60"
  records = [ "${formatlist("0 0 2380 %s.%s.%s.%s",aws_route53_record.master.*.name, var.cluster_name, data.aws_region.current.name, var.cluster_domain )}" ]
}