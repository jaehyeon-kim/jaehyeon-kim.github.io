---
title: Develop and Test Apache Spark Apps for EMR Remotely Using Visual Studio Code
date: 2022-09-07
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
#   - Integrate Schema Registry with MSK Connect
categories:
  - Engineering
tags: 
  - AWS
  - Amazon EMR
  - Apache Spark
  - Pyspark
  - Visual Studio Code
  - Terraform
authors:
  - JaehyeonKim
images: []
cevo: 17
---

This article is originally posted in the [Tech Insights](https://cevo.com.au/tech-insights/) of Cevo Australia - [Link](https://cevo.com.au/post/develop-and-test-apache-spark-apps-for-emr-remotely-using-vscode/).

When we develop a Spark application on EMR, we can use [docker for local development](/blog/2022-05-08-emr-local-dev) or notebooks via [EMR Studio](https://aws.amazon.com/emr/features/studio/) (or [EMR Notebooks](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-managed-notebooks.html)). However, the local development option is not viable if the size of data is large. Also, I am not a fan of notebooks as it is not possible to utilise the features my editor supports such as syntax highlighting, autocomplete and code formatting. Moreover, it is not possible to organise code into modules and to perform unit testing properly with that option. In this post, We will discuss how to set up a remote development environment on an EMR cluster deployed in a private subnet with VPN and the [VS Code remote SSH extension](https://code.visualstudio.com/docs/remote/ssh). Typical Spark development examples will be illustrated while sharing the cluster with multiple users. Overall it brings another effective way of developing Spark apps on EMR, which improves developer experience significantly.


## Architecture

An EMR cluster is deployed in a private subnet and, by default, it is not possible to access it from the developer machine. We can construct a PC-to-PC VPN with [SoftEther VPN](https://www.softether.org/) to establish connection to the master node of the cluster. The VPN server runs in a public subnet, and it is managed by an autoscaling group where only a single instance is maintained. An elastic IP address is associated with the instance so that its public IP doesn't change even if the EC2 instance is recreated. Access from the VPN server to the master node is allowed by an additional security group where the VPN's security group is granted access to the master node. The infrastructure is built using Terraform and the source can be found in the post's [GitHub repository](https://github.com/jaehyeon-kim/emr-remote-dev). 

SoftEther VPN provides the server and client manager programs and they can be downloaded from the [download centre page](https://www.softether-download.com/en.aspx?product=softether). We can create a VPN user using the server manager and the user can establish connection using the client manager. In this way a developer can access an EMR cluster deployed in a private subnet from the developer machine. Check one of my earlier posts titled [Simplify Your Development on AWS with Terraform](/blog/2022-02-06-dev-infra-terraform) for a step-by-step illustration of creating a user and making a connection. The [VS Code Remote - SSH extension](https://code.visualstudio.com/docs/remote/ssh) is used to open a folder in the master node of an EMR cluster. In this way, developer experience can be improved significantly while making use of the full feature set of VS Code. The architecture of the remote development environment is shown below.

![](featured.png#center)

## Infrastructure

The infrastructure of this post is an extension that I illustrated in the [previous post](/blog/2022-02-06-dev-infra-terraform). The resources covered there (VPC, subnets, auto scaling group for VPN etc.) won't be repeated. The main resource in this post is an EMR cluster and the latest EMR 6.7.0 release is deployed with single master and core node instances. It is set up to use the AWS Glue Data Catalog as the metastore for [Hive](https://docs.aws.amazon.com/emr/latest/ReleaseGuide/emr-hive-metastore-glue.html) and [Spark SQL](https://docs.aws.amazon.com/emr/latest/ReleaseGuide/emr-spark-glue.html) by updating the corresponding configuration classification. Additionally, a managed scaling policy is created so that up to 5 instances are added to the core node. Note the additional security group of the master and slave by which the VPN server is granted access to the master and core node instances - the details of that security group is shown below.


```terraform
# infra/emr.tf
resource "aws_emr_cluster" "emr_cluster" {
  name                              = "${local.name}-emr-cluster"
  release_label                     = local.emr.release_label # emr-6.7.0
  service_role                      = aws_iam_role.emr_service_role.arn
  autoscaling_role                  = aws_iam_role.emr_autoscaling_role.arn
  applications                      = local.emr.applications # ["Spark", "Livy", "JupyterEnterpriseGateway", "Hive"]
  ebs_root_volume_size              = local.emr.ebs_root_volume_size
  log_uri                           = "s3n://${aws_s3_bucket.default_bucket[0].id}/elasticmapreduce/"
  step_concurrency_level            = 256
  keep_job_flow_alive_when_no_steps = true
  termination_protection            = false

  ec2_attributes {
    key_name                          = aws_key_pair.emr_key_pair.key_name
    instance_profile                  = aws_iam_instance_profile.emr_ec2_instance_profile.arn
    subnet_id                         = element(tolist(module.vpc.private_subnets), 0)
    emr_managed_master_security_group = aws_security_group.emr_master.id
    emr_managed_slave_security_group  = aws_security_group.emr_slave.id
    service_access_security_group     = aws_security_group.emr_service_access.id
    additional_master_security_groups = aws_security_group.emr_vpn_access.id # grant access to VPN server
    additional_slave_security_groups  = aws_security_group.emr_vpn_access.id # grant access to VPN server
  }

  master_instance_group {
    instance_type  = local.emr.instance_type # m5.xlarge
    instance_count = local.emr.instance_count # 1
  }
  core_instance_group {
    instance_type  = local.emr.instance_type # m5.xlarge
    instance_count = local.emr.instance_count # 1
  }

  configurations_json = <<EOF
    [
      {
          "Classification": "hive-site",
          "Properties": {
              "hive.metastore.client.factory.class": "com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory"
          }
      },
      {
          "Classification": "spark-hive-site",
          "Properties": {
              "hive.metastore.client.factory.class": "com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory"
          }
      }
    ]
  EOF

  tags = local.tags

  depends_on = [module.vpc]
}

resource "aws_emr_managed_scaling_policy" "emr_scaling_policy" {
  cluster_id = aws_emr_cluster.emr_cluster.id

  compute_limits {
    unit_type              = "Instances"
    minimum_capacity_units = 1
    maximum_capacity_units = 5
  }
}
```


The following security group is created to enable access from the VPN server to the EMR instances. Note that the inbound rule is created only when the _local.vpn.to_create_ variable value is true while the security group is created always - if the value is false, the security group has no inbound rule. 


```terraform
# infra/emr.tf
resource "aws_security_group" "emr_vpn_access" {
  name   = "${local.name}-emr-vpn-access"
  vpc_id = module.vpc.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  tags = local.tags
}

resource "aws_security_group_rule" "emr_vpn_inbound" {
  count                    = local.vpn.to_create ? 1 : 0
  type                     = "ingress"
  description              = "VPN access"
  security_group_id        = aws_security_group.emr_vpn_access.id
  protocol                 = "tcp"
  from_port                = 0
  to_port                  = 65535
  source_security_group_id = aws_security_group.vpn[0].id
}
```

### Change to Secret Generation

For configuring the VPN server, we need a [IPsec pre-shared key](https://cloud.google.com/network-connectivity/docs/vpn/how-to/generating-pre-shared-key) and admin password. While those are specified as [variables earlier](/blog/2022-02-06-dev-infra-terraform), they are generated internally in this post for simplicity. The Terraform [shell resource module](https://registry.terraform.io/modules/Invicton-Labs/shell-resource/external/latest) generates and concatenates them with double dashes (--). The corresponding values are parsed into the user data of the VPN instance and the string is saved into a file to be used for configuring the VPN server manager.  


```terraform
## create VPN secrets - IPsec Pre-Shared Key and admin password for VPN
##  see https://cloud.google.com/network-connectivity/docs/vpn/how-to/generating-pre-shared-key
module "vpn_secrets" {
  source = "Invicton-Labs/shell-resource/external"

  # generate <IPsec Pre-Shared Key>--<admin password> and parsed in vpn module
  command_unix = "echo $(openssl rand -base64 24)--$(openssl rand -base64 24)"
}

resource "local_file" "vpn_secrets" {
  content  = module.vpn_secrets.stdout
  filename = "${path.module}/secrets/vpn_secrets"
}

module "vpn" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "~> 6.5"
  count   = local.vpn.to_create ? 1 : 0

  name = "${local.name}-vpn-asg"

  key_name            = local.vpn.to_create ? aws_key_pair.key_pair[0].key_name : null
  vpc_zone_identifier = module.vpc.public_subnets
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1

  image_id                 = data.aws_ami.amazon_linux_2.id
  instance_type            = element([for s in local.vpn.spot_override : s.instance_type], 0)
  security_groups          = [aws_security_group.vpn[0].id]
  iam_instance_profile_arn = aws_iam_instance_profile.vpn[0].arn

  # Launch template
  create_launch_template = true
  update_default_version = true

  user_data = base64encode(join("\n", [
    "#cloud-config",
    yamlencode({
      # https://cloudinit.readthedocs.io/en/latest/topics/modules.html
      write_files : [
        {
          path : "/opt/vpn/bootstrap.sh",
          content : templatefile("${path.module}/scripts/bootstrap.sh", {
            aws_region     = local.region,
            allocation_id  = aws_eip.vpn[0].allocation_id,
            vpn_psk        = split("--", replace(module.vpn_secrets.stdout, "\n", ""))[0], # specify IPsec pre-shared key
            admin_password = split("--", replace(module.vpn_secrets.stdout, "\n", ""))[1]  # specify admin password
          }),
          permissions : "0755",
        }
      ],
      runcmd : [
        ["/opt/vpn/bootstrap.sh"],
      ],
    })
  ]))

  ...

  tags = local.tags
}
```

After deploying all the resources, it is good to go to the next section if we're able to connect to the VPN server as shown below.

![](01-vpn-connection.png#center)

## Preparation

### User Creation

While we are able to use the default hadoop user for development, we can add additional users to share the cluster as well. First let's access the master node via ssh as shown below. Note the access key is stored in the _infra/key-pair_ folder and the master private DNS name can be obtained from the _emr_cluster_master_dns _output value.


```bash
# access to the master node via ssh
jaehyeon@cevo$ export EMR_MASTER_DNS=$(terraform -chdir=./infra output --raw emr_cluster_master_dns)
jaehyeon@cevo$ ssh -i infra/key-pair/emr-remote-dev-emr-key.pem hadoop@$EMR_MASTER_DNS
The authenticity of host 'ip-10-0-113-113.ap-southeast-2.compute.internal (10.0.113.113)' can't be established.
ECDSA key fingerprint is SHA256:mNdgPWnDkCG/6IsUDdHAETe/InciOatb8jwELnwfWR4.
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added 'ip-10-0-113-113.ap-southeast-2.compute.internal,10.0.113.113' (ECDSA) to the list of known hosts.

       __|  __|_  )
       _|  (     /   Amazon Linux 2 AMI
      ___|\___|___|

https://aws.amazon.com/amazon-linux-2/
17 package(s) needed for security, out of 38 available
Run "sudo yum update" to apply all updates.
                                                                   
EEEEEEEEEEEEEEEEEEEE MMMMMMMM           MMMMMMMM RRRRRRRRRRRRRRR    
E::::::::::::::::::E M:::::::M         M:::::::M R::::::::::::::R  
EE:::::EEEEEEEEE:::E M::::::::M       M::::::::M R:::::RRRRRR:::::R
  E::::E       EEEEE M:::::::::M     M:::::::::M RR::::R      R::::R
  E::::E             M::::::M:::M   M:::M::::::M   R:::R      R::::R
  E:::::EEEEEEEEEE   M:::::M M:::M M:::M M:::::M   R:::RRRRRR:::::R
  E::::::::::::::E   M:::::M  M:::M:::M  M:::::M   R:::::::::::RR  
  E:::::EEEEEEEEEE   M:::::M   M:::::M   M:::::M   R:::RRRRRR::::R  
  E::::E             M:::::M    M:::M    M:::::M   R:::R      R::::R
  E::::E       EEEEE M:::::M     MMM     M:::::M   R:::R      R::::R
EE:::::EEEEEEEE::::E M:::::M             M:::::M   R:::R      R::::R
E::::::::::::::::::E M:::::M             M:::::M RR::::R      R::::R
EEEEEEEEEEEEEEEEEEEE MMMMMMM             MMMMMMM RRRRRR      RRRRRR
                                                                   
[hadoop@ip-10-0-113-113 ~]$
```


A user can be created as shown below. Optionally the user is added to the sudoers file so that the user is allowed to run a command as the root user without specifying the password. Note this is a shortcut only, and please check [this page](https://www.digitalocean.com/community/tutorials/how-to-edit-the-sudoers-file) for proper usage of editing the sudoers file. 


```bash
# create a user and add to sudoers
[hadoop@ip-10-0-113-113 ~]$ sudo adduser jaehyeon
[hadoop@ip-10-0-113-113 ~]$ ls /home/
ec2-user  emr-notebook  hadoop  jaehyeon
[hadoop@ip-10-0-113-113 ~]$ sudo su
[root@ip-10-0-113-113 hadoop]# chmod +w /etc/sudoers
[root@ip-10-0-113-113 hadoop]# echo "jaehyeon  ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
```


Also, as described in the [EMR documentation](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-kerberos-configuration-users.html), we must add the HDFS user directory for the user account and grant ownership of the directory so that the user is allowed to log in to the cluster to run Hadoop jobs.


```bash
[root@ip-10-0-113-113 hadoop]# sudo su - hdfs
# create user directory
-bash-4.2$ hdfs dfs -mkdir /user/jaehyeon
SLF4J: Class path contains multiple SLF4J bindings.
SLF4J: Found binding in [jar:file:/usr/lib/hadoop/lib/slf4j-log4j12-1.7.25.jar!/org/slf4j/impl/StaticLoggerBinder.class]
SLF4J: Found binding in [jar:file:/usr/lib/tez/lib/slf4j-reload4j-1.7.36.jar!/org/slf4j/impl/StaticLoggerBinder.class]
SLF4J: See http://www.slf4j.org/codes.html#multiple_bindings for an explanation.
SLF4J: Actual binding is of type [org.slf4j.impl.Log4jLoggerFactory]
# update directory ownership
-bash-4.2$ hdfs dfs -chown jaehyeon:jaehyeon /user/jaehyeon
SLF4J: Class path contains multiple SLF4J bindings.
SLF4J: Found binding in [jar:file:/usr/lib/hadoop/lib/slf4j-log4j12-1.7.25.jar!/org/slf4j/impl/StaticLoggerBinder.class]
SLF4J: Found binding in [jar:file:/usr/lib/tez/lib/slf4j-reload4j-1.7.36.jar!/org/slf4j/impl/StaticLoggerBinder.class]
SLF4J: See http://www.slf4j.org/codes.html#multiple_bindings for an explanation.
SLF4J: Actual binding is of type [org.slf4j.impl.Log4jLoggerFactory]
# check directories in /user
-bash-4.2$ hdfs dfs -ls /user
SLF4J: Class path contains multiple SLF4J bindings.
SLF4J: Found binding in [jar:file:/usr/lib/hadoop/lib/slf4j-log4j12-1.7.25.jar!/org/slf4j/impl/StaticLoggerBinder.class]
SLF4J: Found binding in [jar:file:/usr/lib/tez/lib/slf4j-reload4j-1.7.36.jar!/org/slf4j/impl/StaticLoggerBinder.class]
SLF4J: See http://www.slf4j.org/codes.html#multiple_bindings for an explanation.
SLF4J: Actual binding is of type [org.slf4j.impl.Log4jLoggerFactory]
Found 7 items
drwxrwxrwx   - hadoop   hdfsadmingroup          0 2022-09-03 10:19 /user/hadoop
drwxr-xr-x   - mapred   mapred                  0 2022-09-03 10:19 /user/history
drwxrwxrwx   - hdfs     hdfsadmingroup          0 2022-09-03 10:19 /user/hive
drwxr-xr-x   - jaehyeon jaehyeon                0 2022-09-03 10:39 /user/jaehyeon
drwxrwxrwx   - livy     livy                    0 2022-09-03 10:19 /user/livy
drwxrwxrwx   - root     hdfsadmingroup          0 2022-09-03 10:19 /user/root
drwxrwxrwx   - spark    spark                   0 2022-09-03 10:19 /user/spark
```


Finally, we need to add the public key to the _.ssh/authorized_keys_ file in order to set up [public key authentication](https://www.linode.com/docs/guides/use-public-key-authentication-with-ssh/) for SSH access.


```bash
# add public key
[hadoop@ip-10-0-113-113 ~]$ sudo su - jaehyeon
[jaehyeon@ip-10-0-113-113 ~]$ mkdir .ssh
[jaehyeon@ip-10-0-113-113 ~]$ chmod 700 .ssh
[jaehyeon@ip-10-0-113-113 ~]$ touch .ssh/authorized_keys
[jaehyeon@ip-10-0-113-113 ~]$ chmod 600 .ssh/authorized_keys
[jaehyeon@ip-10-0-113-113 ~]$ PUBLIC_KEY="<SSH-PUBLIC-KEY>"
[jaehyeon@ip-10-0-113-113 ~]$ echo $PUBLIC_KEY > .ssh/authorized_keys
```

### Clone Repository

As we can open a folder in the master node, the GitHub repository is cloned to each user's home folder to open later.


```bash
[hadoop@ip-10-0-113-113 ~]$ sudo yum install git
[hadoop@ip-10-0-113-113 ~]$ git clone https://github.com/jaehyeon-kim/emr-remote-dev.git
[hadoop@ip-10-0-113-113 ~]$ ls
emr-remote-dev
[hadoop@ip-10-0-113-113 ~]$ sudo su - jaehyeon
[jaehyeon@ip-10-0-113-113 ~]$ git clone https://github.com/jaehyeon-kim/emr-remote-dev.git
[jaehyeon@ip-10-0-113-113 ~]$ ls
emr-remote-dev
```

## Access to EMR Cluster

Now we have two users that have access to the EMR cluster and their connection details are saved into an [SSH configuration file](https://linuxize.com/post/using-the-ssh-config-file/) as shown below.


```conf
Host emr-hadoop
  HostName ip-10-0-113-113.ap-southeast-2.compute.internal
  User hadoop
  ForwardAgent yes
  IdentityFile C:\Users\<username>\.ssh\emr-remote-dev-emr-key.pem
Host emr-jaehyeon
  HostName ip-10-0-113-113.ap-southeast-2.compute.internal
  User jaehyeon
  ForwardAgent yes
  IdentityFile C:\Users\<username>\.ssh\id_rsa
```


Then we can see the connection details in the remote explorer menu of VS Code. Note the [remote SSH extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh) should be installed for it. On right-clicking the mouse on the emr-hadoop connection, we can select the option to connect to the host in a new window.

![](02-01-ssh-connect.png#center)


In a new window, a menu pops up to select the platform of the remote host.

![](02-02-ssh-connect.png#center)


If it's the first time connecting to the server, it requests to confirm whether you trust and want to continue connecting to the host. We can hit Continue.

![](02-03-ssh-connect.png#center)


Once we are connected, we can open a folder in the server. On selecting _File > Open Folder…_ menu, we can see a list of folders that we can open. Let's open the repository folder we cloned earlier.

![](02-04-ssh-connect.png#center)


VS Code asks whether we trust the authors of the files in this folder and we can hit Yes.

![](02-05-ssh-connect.png#center)


Now access to the server with the remote SSH extension is complete and we can check it by opening a terminal where it shows the typical EMR shell.

![](02-06-ssh-connect.png#center)

### Python Configuration

We can install the Python extension at minimum and it indicates the extension will be installed in the remote server (_emr-hadoop_).

![](03-01-python-config.png#center)

We'll use the Pyspark and py4j packages that are included in the existing spark distribution. It can be done simply by creating an [.env file](https://code.visualstudio.com/docs/python/environments#_use-of-the-pythonpath-variable) that adds the relevant paths to the *PYTHONPATH* variable. In the following screenshot, you see that there is no warning to import *SparkSession*.

![](03-02-python-config.png#center)


## Remote Development


### Transform Data

It is a simple Spark application that reads a sample NY taxi trip dataset from a public S3 bucket. Once loaded, it converts the pick-up and drop-off datetime columns from string to timestamp followed by writing the transformed data to a destination S3 bucket. It finishes by creating a Glue table with the transformed data.


```python
# tripdata_write.py
from pyspark.sql import SparkSession

from utils import to_timestamp_df

if __name__ == "__main__":
    spark = SparkSession.builder.appName("Trip Data").enableHiveSupport().getOrCreate()

    dbname = "tripdata"
    tblname = "ny_taxi"
    bucket_name = "emr-remote-dev-590312749310-ap-southeast-2"
    dest_path = f"s3://{bucket_name}/{tblname}/"
    src_path = "s3://aws-data-analytics-workshops/shared_datasets/tripdata/"
    # read csv
    ny_taxi = spark.read.option("inferSchema", "true").option("header", "true").csv(src_path)
    ny_taxi = to_timestamp_df(ny_taxi, ["lpep_pickup_datetime", "lpep_dropoff_datetime"])
    ny_taxi.printSchema()
    # write parquet
    ny_taxi.write.mode("overwrite").parquet(dest_path)
    # create glue table
    ny_taxi.createOrReplaceTempView(tblname)
    spark.sql(f"CREATE DATABASE IF NOT EXISTS {dbname}")
    spark.sql(f"USE {dbname}")
    spark.sql(
        f"""CREATE TABLE IF NOT EXISTS {tblname}
            USING PARQUET
            LOCATION '{dest_path}'
            AS SELECT * FROM {tblname}
        """
    )
```


As the spark application should run in a cluster, we need to copy it into HDFS. For simplicity, I copied the current folder into the /user/hadoop/emr-remote-dev directory.


```bash
# copy current folder into /user/hadoop/emr-remote-dev
[hadoop@ip-10-0-113-113 emr-remote-dev]$ hdfs dfs -put . /user/hadoop/emr-remote-dev
SLF4J: Class path contains multiple SLF4J bindings.
SLF4J: Found binding in [jar:file:/usr/lib/hadoop/lib/slf4j-log4j12-1.7.25.jar!/org/slf4j/impl/StaticLoggerBinder.class]
SLF4J: Found binding in [jar:file:/usr/lib/tez/lib/slf4j-reload4j-1.7.36.jar!/org/slf4j/impl/StaticLoggerBinder.class]
SLF4J: See http://www.slf4j.org/codes.html#multiple_bindings for an explanation.
SLF4J: Actual binding is of type [org.slf4j.impl.Log4jLoggerFactory]
# check contents in /user/hadoop/emr-remote-dev
[hadoop@ip-10-0-113-113 emr-remote-dev]$ hdfs dfs -ls /user/hadoop/emr-remote-dev
SLF4J: Class path contains multiple SLF4J bindings.
SLF4J: Found binding in [jar:file:/usr/lib/hadoop/lib/slf4j-log4j12-1.7.25.jar!/org/slf4j/impl/StaticLoggerBinder.class]
SLF4J: Found binding in [jar:file:/usr/lib/tez/lib/slf4j-reload4j-1.7.36.jar!/org/slf4j/impl/StaticLoggerBinder.class]
SLF4J: See http://www.slf4j.org/codes.html#multiple_bindings for an explanation.
SLF4J: Actual binding is of type [org.slf4j.impl.Log4jLoggerFactory]
Found 10 items
-rw-r--r--   1 hadoop hdfsadmingroup         93 2022-09-03 11:11 /user/hadoop/emr-remote-dev/.env
drwxr-xr-x   - hadoop hdfsadmingroup          0 2022-09-03 11:11 /user/hadoop/emr-remote-dev/.git
-rw-r--r--   1 hadoop hdfsadmingroup        741 2022-09-03 11:11 /user/hadoop/emr-remote-dev/.gitignore
drwxr-xr-x   - hadoop hdfsadmingroup          0 2022-09-03 11:11 /user/hadoop/emr-remote-dev/.vscode
-rw-r--r--   1 hadoop hdfsadmingroup         25 2022-09-03 11:11 /user/hadoop/emr-remote-dev/README.md
drwxr-xr-x   - hadoop hdfsadmingroup          0 2022-09-03 11:11 /user/hadoop/emr-remote-dev/infra
-rw-r--r--   1 hadoop hdfsadmingroup        873 2022-09-03 11:11 /user/hadoop/emr-remote-dev/test_utils.py
-rw-r--r--   1 hadoop hdfsadmingroup        421 2022-09-03 11:11 /user/hadoop/emr-remote-dev/tripdata_read.sh
-rw-r--r--   1 hadoop hdfsadmingroup       1066 2022-09-03 11:11 /user/hadoop/emr-remote-dev/tripdata_write.py
-rw-r--r--   1 hadoop hdfsadmingroup        441 2022-09-03 11:11 /user/hadoop/emr-remote-dev/utils.py
```


The app can be submitted by specifying the HDFS locations of the app and source file. It is deployed to the YARN cluster with the client deployment mode. In this way, data processing can be performed by executors in the core node and we are able to check execution details in the same terminal.


```bash
[hadoop@ip-10-0-113-113 emr-remote-dev]$ spark-submit \
  --master yarn \
  --deploy-mode client \
  --py-files hdfs:/user/hadoop/emr-remote-dev/utils.py \
  hdfs:/user/hadoop/emr-remote-dev/tripdata_write.py
```

Once the app completes, we can see that a Glue database named _tripdata_ is created, and it includes a table named _ny_taxi_.

![](04-data-write.png#center)

### Read Data

We can connect to the cluster with the other user account as well. Below shows an example of the PySpark shell that reads data from the table created earlier. It just reads the Glue table and adds a column of trip duration followed by showing the summary statistics of key columns.

![](05-data-read.png#center)

### Unit Test

The Spark application uses a custom function that converts the data type of one or more columns from string to timestamp - `to_timestamp_df()`. The source of the function and the testing script can be found below.


```python
# utils.py
from typing import List, Union
from pyspark.sql import DataFrame
from pyspark.sql.functions import col, to_timestamp

def to_timestamp_df(
    df: DataFrame, fields: Union[List[str], str], format: str = "M/d/yy H:mm"
) -> DataFrame:
    fields = [fields] if isinstance(fields, str) else fields
    for field in fields:
        df = df.withColumn(field, to_timestamp(col(field), format))
    return df

# test_utils.py
import pytest
import datetime
from pyspark.sql import SparkSession
from py4j.protocol import Py4JError

from utils import to_timestamp_df


@pytest.fixture(scope="session")
def spark():
    return (
        SparkSession.builder.master("local")
        .appName("test")
        .config("spark.submit.deployMode", "client")
        .getOrCreate()
    )


def test_to_timestamp_success(spark):
    raw_df = spark.createDataFrame(
        [("1/1/17 0:01",)],
        ["date"],
    )

    test_df = to_timestamp_df(raw_df, "date", "M/d/yy H:mm")
    for row in test_df.collect():
        assert row["date"] == datetime.datetime(2017, 1, 1, 0, 1)


def test_to_timestamp_bad_format(spark):
    raw_df = spark.createDataFrame(
        [("1/1/17 0:01",)],
        ["date"],
    )

    with pytest.raises(Py4JError):
        to_timestamp_df(raw_df, "date", "M/d/yy HH:mm").collect()
```


For unit testing, we need to install the Pytest package and export the *PYTHONPATH* variable that can be found in the .env file. Note, as testing can be run with a local Spark session, the testing package can only be installed in the master node. Below shows an example test run output.

![](06-data-test.png#center)

## Summary

In this post, we discussed how to set up a remote development environment on an EMR cluster. A cluster is deployed in a private subnet, access from a developer machine is established via PC-to-PC VPN and the VS Code Remote - SSH extension is used to perform remote development. Aside from the default hadoop user, an additional user account is created to show how to share the cluster with multiple users and spark development examples are illustrated with those user accounts. Overall the remote development brings another effective option to develop spark applications on EMR, which improves developer experience significantly.
