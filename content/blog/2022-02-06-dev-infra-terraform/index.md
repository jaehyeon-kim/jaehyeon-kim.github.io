---
title: Simplify Your Development on AWS with Terraform
date: 2022-02-06
draft: false
featured: false
draft: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
# series:
#   - Data Lake Demo Using Change Data Capture
categories:
  - Engineering
tags: 
  - AWS
  - Terraform
  - VPN
authors:
  - JaehyeonKim
images: []
cevo: 9
---

When I wrote my data lake demo series ([part 1](/blog/2021-12-05-datalake-demo-part1), [part 2](/blog/2021-12-12-datalake-demo-part2) and [part 3](/blog/2021-12-19-datalake-demo-part3)) recently, I used an Aurora PostgreSQL, MSK and EMR cluster. All of them were deployed to private subnets and dedicated infrastructure was created using CloudFormation. Using the infrastructure as code (IaC) tool helped a lot, but it resulted in creating 7 CloudFormation stacks, which was a bit harder to manage in the end. Then I looked into how to simplify building infrastructure and managing resources on AWS and decided to use Terraform instead. I find it has useful constructs (e.g. [meta-arguments](https://blog.knoldus.com/meta-arguments-in-terraform/)) to make it simpler to create and manage resources. It also has a wide range of useful [modules](https://registry.terraform.io/namespaces/terraform-aws-modules) that facilitate development significantly. In this post, we’ll build an infrastructure for development on AWS with Terraform. A VPN server will also be included in order to improve developer experience by accessing resources in private subnets from developer machines.

## Architecture

The infrastructure that we’ll discuss in this post is shown below. The database is deployed in a private subnet, and it is not possible to access it from the developer machine. We can construct a PC-to-PC VPN with [SoftEther VPN](https://www.softether.org/). The VPN server runs in a public subnet, and it is managed by an autoscaling group where only a single instance will be maintained. An elastic IP address is associated by a bootstrap script so that its public IP doesn't change even if the EC2 instance is recreated. We can add users with the server manager program, and they can access the server with the client program. Access from the VPN server to the database is allowed by adding an inbound rule where the source security group ID is set to the VPN server’s security group ID. Note that another option is [AWS Client VPN](https://aws.amazon.com/vpn/client-vpn/), but it is way more expensive. We’ll create 2 private subnets, and it’ll cost $0.30/hour for endpoint association in the Sydney region. It also charges $0.05/hour for each connection and the minimum charge will be $0.35/hour. On the other hand, the SorftEther VPN server runs in the `t3.nano` instance and its cost is only $0.0066/hour.

![](featured.png#center)

Even developing a single database can result in a stack of resources and Terraform can be of great help to create and manage those resources. Also, VPN can improve developer experience significantly as it helps access them from developer machines. In this post, it’ll be illustrated how to access a database but access to other resources such as MSK, EMR, ECS and EKS can also be made.


## Infrastructure

[Terraform can be installed](https://learn.hashicorp.com/tutorials/terraform/install-cli) in multiple ways and the CLI has intuitive commands to manage AWS infrastructure. Key commands are



* [init](https://www.terraform.io/cli/commands/init) - It is used to initialize a working directory containing Terraform configuration files.
* [plan](https://www.terraform.io/cli/commands/plan) - It creates an execution plan, which lets you preview the changes that Terraform plans to make to your infrastructure.
* [apply](https://www.terraform.io/cli/commands/apply) - It executes the actions proposed in a Terraform plan.
* [destroy](https://www.terraform.io/cli/commands/destroy) - It is a convenient way to destroy all remote objects managed by a particular Terraform configuration.

The [**GitHub repository**](https://github.com/jaehyeon-kim/dev-infra-demo-terraform) for this post has the following directory structure. [Terraform resources](https://www.terraform.io/language/resources) are grouped into 4 files, and they’ll be discussed further below. The remaining files are supporting elements and their details can be found in the [language reference](https://www.terraform.io/language).


```bash
$ tree
.
├── README.md
├── _data.tf
├── _outputs.tf
├── _providers.tf
├── _variables.tf
├── aurora.tf
├── keypair.tf
├── scripts
│   └── bootstrap.sh
├── vpc.tf
└── vpn.tf

1 directory, 10 files
```

### VPC

We can use the [AWS VPC module](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest) to construct a VPC. A [Terraform module](https://www.terraform.io/language/modules) is a container for multiple resources, and it makes it easier to manage related resources. A VPC with 2 availability zones is defined and private/public subnets are configured to each of them. Optionally a NAT gateway is added only to a single availability zone.


```terraform
# vpc.tf
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${local.resource_prefix}-vpc"
  cidr = "10.${var.class_b}.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets = ["10.${var.class_b}.0.0/19", "10.${var.class_b}.32.0/19"]
  public_subnets  = ["10.${var.class_b}.64.0/19", "10.${var.class_b}.96.0/19"]

  enable_nat_gateway = true
  single_nat_gateway = true
  one_nat_gateway_per_az = false
}
```

### Key Pair

An optional key pair is created. It can be used to access an EC2 instance via SSH. The PEM file will be saved to the _key-pair_ folder once created.


```terraform
# keypair.tf
resource "tls_private_key" "pk" {
  count     = var.key_pair_create ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "key_pair" {
  count      = var.key_pair_create ? 1 : 0
  key_name   = "${local.resource_prefix}-key"
  public_key = tls_private_key.pk[0].public_key_openssh
}

resource "local_file" "pem_file" {
  count             = var.key_pair_create ? 1 : 0
  filename          = pathexpand("${path.module}/key-pair/${local.resource_prefix}-key.pem")
  file_permission   = "0400"
  sensitive_content = tls_private_key.pk[0].private_key_pem
}
```

### VPN

The [AWS Auto Scaling Group (ASG) module](https://registry.terraform.io/modules/HDE/autoscaling/aws/latest) is used to manage the SoftEther VPN server. The ASG maintains a single EC2 instance in one of the public subnets. The user data script (_bootstrap.sh_) is configured to run at launch and it’ll be discussed below. Note that there are other resources that are necessary to make the VPN server to work correctly and those can be found in the [vpn.tf](https://github.com/jaehyeon-kim/dev-infra-demo-terraform/blob/main/vpn.tf). Also note that the VPN resource requires a number of configuration values. While most of them have default values or are automatically determined, the [IPsec Pre-Shared key](https://cloud.google.com/network-connectivity/docs/vpn/how-to/generating-pre-shared-key) (_vpn_psk_) and administrator password (_admin_password_) do not have default values. They need to be specified while running the _plan_, _apply_ and _destroy _commands. Finally, if the variable _vpn_limit_ingress_ is set to true, the inbound rules of the VPN security group is limited to the running machine’s IP address.


```terraform
# _variables.tf
variable "vpn_create" {
  description = "Whether to create a VPN instance"
  default = true
}

variable "vpn_limit_ingress" {
  description = "Whether to limit the CIDR block of VPN security group inbound rules."
  default = true
}

variable "vpn_use_spot" {
  description = "Whether to use spot or on-demand EC2 instance"
  default = false
}

variable "vpn_psk" {
  description = "The IPsec Pre-Shared Key"
  type        = string
  sensitive   = true
}

variable "admin_password" {
  description = "SoftEther VPN admin / database master password"
  type        = string
  sensitive   = true
}

locals {
  ...
  local_ip_address  = "${chomp(data.http.local_ip_address.body)}/32"
  vpn_ingress_cidr  = var.vpn_limit_ingress ? local.local_ip_address : "0.0.0.0/0"
  vpn_spot_override = [
    { instance_type: "t3.nano" },
    { instance_type: "t3a.nano" },    
  ]
}

# vpn.tf
module "vpn" {
  source  = "terraform-aws-modules/autoscaling/aws"
  count   = var.vpn_create ? 1 : 0

  name = "${local.resource_prefix}-vpn-asg"

  key_name            = var.key_pair_create ? aws_key_pair.key_pair[0].key_name : null
  vpc_zone_identifier = module.vpc.public_subnets
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1

  image_id                  = data.aws_ami.amazon_linux_2.id
  instance_type             = element([for s in local.vpn_spot_override: s.instance_type], 0)
  security_groups           = [aws_security_group.vpn[0].id]
  iam_instance_profile_arn  = aws_iam_instance_profile.vpn[0].arn

  # Launch template
  create_lt              = true
  update_default_version = true

  user_data_base64 = base64encode(join("\n", [
    "#cloud-config",
    yamlencode({
      # https://cloudinit.readthedocs.io/en/latest/topics/modules.html
      write_files : [
        {
          path : "/opt/vpn/bootstrap.sh",
          content : templatefile("${path.module}/scripts/bootstrap.sh", {
            aws_region      = var.aws_region,
            allocation_id   = aws_eip.vpn[0].allocation_id,
            vpn_psk         = var.vpn_psk,
            admin_password  = var.admin_password
          }),
          permissions : "0755",
        }
      ],
      runcmd : [
        ["/opt/vpn/bootstrap.sh"],
      ],
    })
  ]))

  # Mixed instances
  use_mixed_instances_policy = true
  mixed_instances_policy = {
    instances_distribution = {
      on_demand_base_capacity                  = var.vpn_use_spot ? 0 : 1
      on_demand_percentage_above_base_capacity = var.vpn_use_spot ? 0 : 100
      spot_allocation_strategy                 = "capacity-optimized"
    }
    override = local.vpn_spot_override
  }

  tags_as_map = {
    "Name" = "${local.resource_prefix}-vpn-asg"
  }
}

resource "aws_eip" "vpn" {
  count = var.vpn_create ? 1 : 0
  tags  = {
    "Name" = "${local.resource_prefix}-vpn-eip"
  }
}

...
```


The bootstrap script associates the elastic IP address followed by starting the SoftEther VPN server by a [Docker container](https://github.com/siomiz/SoftEtherVPN). It accepts the pre-shared key (_vpn_psk_) and administrator password (_admin_password_) as environment variables. Also, the Virtual Hub name is set to _DEFAULT_.


```bash
# scripts/bootstrap.sh
#!/bin/bash -ex

## Allocate elastic IP and disable source/destination checks
TOKEN=$(curl --silent --max-time 60 -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 30")
INSTANCEID=$(curl --silent --max-time 60 -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
aws --region ${aws_region} ec2 associate-address --instance-id $INSTANCEID --allocation-id ${allocation_id}
aws --region ${aws_region} ec2 modify-instance-attribute --instance-id $INSTANCEID --source-dest-check "{\"Value\": false}"

## Start SoftEther VPN server
yum update -y && yum install docker -y
systemctl enable docker.service && systemctl start docker.service

docker pull siomiz/softethervpn:debian
docker run -d \
  --cap-add NET_ADMIN \
  --name softethervpn \
  --restart unless-stopped \
  -p 500:500/udp -p 4500:4500/udp -p 1701:1701/tcp -p 1194:1194/udp -p 5555:5555/tcp -p 443:443/tcp \
  -e PSK=${vpn_psk} \
  -e SPW=${admin_password} \
  -e HPW=DEFAULT \
  siomiz/softethervpn:debian
```

### Database

An Aurora PostgreSQL cluster is created using the [AWS RDS Aurora module](https://registry.terraform.io/modules/terraform-aws-modules/rds-aurora/aws/latest). It is set to have only a single instance and is deployed to a private subnet. Note that a security group (_vpn_access_) is created that allows access from the VPN server, and it is added to _vpc_security_group_ids_.


```terraform
# aurora.tf
module "aurora" {
  source  = "terraform-aws-modules/rds-aurora/aws"

  name                        = "${local.resource_prefix}-db-cluster"
  engine                      = "aurora-postgresql"
  engine_version              = "13"
  auto_minor_version_upgrade  = false

  instances = {
    1 = {
      instance_class = "db.t3.medium"
    }
  }

  vpc_id                 = module.vpc.vpc_id
  db_subnet_group_name   = aws_db_subnet_group.aurora.id
  create_db_subnet_group = false
  create_security_group  = true
  vpc_security_group_ids = [aws_security_group.vpn_access.id]

  iam_database_authentication_enabled = false
  create_random_password              = false
  master_password                     = var.admin_password
  database_name                       = local.database_name
 
  apply_immediately   = true
  skip_final_snapshot = true

  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.id
  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = {
    Name = "${local.resource_prefix}-db-cluster"
  }
}

resource "aws_db_subnet_group" "aurora" {
  name       = "${local.resource_prefix}-db-subnet-group"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name = "${local.resource_prefix}-db-subnet-group"
  }
}

...

resource "aws_security_group" "vpn_access" {
  name   = "${local.resource_prefix}-db-security-group"
  vpc_id = module.vpc.vpc_id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "aurora_vpn_inbound" {
  count                    = var.vpn_create ? 1 : 0
  type                     = "ingress"
  description              = "VPN access"
  security_group_id        = aws_security_group.vpn_access.id
  protocol                 = "tcp"
  from_port                = "5432"
  to_port                  = "5432"
  source_security_group_id = aws_security_group.vpn[0].id
}
```



## VPN Configuration

Both the VPN Server Manager and Client can be obtained from the [download centre](https://www.softether-download.com/en.aspx?product=softether). The server and client configuration are illustrated below.


### VPN Server

We can begin with adding a new setting.

![](vpn-server-01.png#center)

We need to fill in the input fields in the red boxes below. It’s possible to use the elastic IP address as the host name and the administrator password should match to what is used for Terraform.

![](vpn-server-02.png#center)

Then we can make a connection to the server by clicking the connect button.

![](vpn-server-03.png#center)

If it’s the first attempt, we’ll see the following pop-up message and we can click yes to set up the IPsec.

![](vpn-server-04.png#center)

In the dialog, we just need to enter the IPsec Pre-Shared key and click ok.

![](vpn-server-05.png#center)

Once a connection is made successfully, we can manage the [Virtual Hub](https://www.softether.org/4-docs/1-manual/3._SoftEther_VPN_Server_Manual/3.4_Virtual_Hub_Functions) by clicking the manage virtual hub button. Note that we created a Virtual Hub named _DEFAULT_ and the session will be established on that Virtual Hub.

![](vpn-server-06.png#center)

We can create a new user by clicking the manage users button.

![](vpn-server-07.png#center)

And clicking the new button.

![](vpn-server-08.png#center)

For simplicity, we can use Password Authentication as the auth type and enter the username and password.

![](vpn-server-09.png#center)

A new user is created, and we can use the credentials on the client program to make a connection to the server.


### VPN Client

We can add a VPN connection by clicking the menu shown below.

![](vpn-client-01.png#center)

We’ll need to create a Virtual Network Adapter and should click the yes button.

![](vpn-client-02.png#center)

In the new dialog, we can add the adapter name and hit ok. Note we should have the administrator privilege to create a new adapter.

![](vpn-client-03.png#center)

Then a new dialog box will be shown. We can add a connection by entering the input fields in the red boxes below. The VPN server details should match to what are created by Terraform and the user credentials that are created in the previous section can be used.

![](vpn-client-04.png#center)

Once a connection is added, we can make a connection to the VPN server by right-clicking the item and clicking the connect menu.

![](vpn-client-05.png#center)

We can see that the status is changed into connected.

![](vpn-client-06.png#center)

Once the VPN server is connected, we can access the database that is deployed in the private subnet. A connection is tested by a database client, and it is shown that the connection is successful.

![](vpn-connection.png#center)

## Summary

In this post, we discussed how to set up a development infrastructure on AWS with Terraform. Terraform is used as an effective way of managing resources on AWS. An Aurora PostgreSQL cluster is created in a private subnet and SoftEther VPN is configured to access the database from the developer machine.
