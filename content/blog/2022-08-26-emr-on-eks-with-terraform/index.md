---
title: Manage EMR on EKS with Terraform
date: 2022-08-26
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
  - Data Engineering
tags: 
  - AWS
  - Amazon EKS
  - Amazon EMR
  - Apache Spark
  - Kubernetes
  - Terraform
authors:
  - JaehyeonKim
images: []
cevo: 16
---

[Amazon EMR on EKS](https://aws.amazon.com/emr/features/eks/) is a deployment option for Amazon EMR that allows you to automate the provisioning and management of open-source big data frameworks on EKS. While [eksctl](https://eksctl.io/) is popular for working with [Amazon EKS](https://aws.amazon.com/eks/) clusters, it has limitations when it comes to building infrastructure that integrates multiple AWS services. Also, it is not straightforward to update EKS cluster resources incrementally with it. On the other hand [Terraform](https://www.terraform.io/) can be an effective tool for managing infrastructure that includes not only EKS and EMR virtual clusters but also other AWS resources. Moreover, Terraform has a wide range of [modules](https://www.terraform.io/language/modules), and it can even be simpler to build and manage infrastructure using those compared to the CLI tool. In this post, we’ll discuss how to provision and manage Spark jobs on EMR on EKS with Terraform. [Amazon EKS Blueprints for Terraform](https://aws-ia.github.io/terraform-aws-eks-blueprints/v4.7.0/) will be used for provisioning EKS, EMR virtual cluster and related resources. Also, Spark job autoscaling will be managed by [Karpenter](https://karpenter.sh/) where two Spark jobs with and without [Dynamic Resource Allocation (DRA)](https://spark.apache.org/docs/latest/job-scheduling.html#dynamic-resource-allocation) will be compared.


## Infrastructure

When a user submits a Spark job, multiple Pods (controller, driver and executors) will be deployed to the EKS cluster that is registered with EMR. In general, Karpenter provides just-in-time capacity for unschedulable Pods by creating (and terminating afterwards) additional nodes. We can configure the pod templates of a Spark job so that all the Pods are managed by Karpenter. In this way, we are able to run it only in transient nodes. Karpenter simplifies autoscaling by provisioning just-in-time capacity, and it also reduces scheduling latency. The source can be found in the post’s [**GitHub repository**](https://github.com/jaehyeon-kim/emr-on-eks-terraform).

![](featured.png#center)

### VPC

Both private and public subnets are created in three availability zones using the [AWS VPC module](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/3.14.2). The first two subnet tags are in relation to the [subnet requirements and considerations](https://docs.aws.amazon.com/eks/latest/userguide/network_reqs.html) of Amazon EKS. The last one of the private subnet tags (_karpenter.sh/discovery_) is added so that [Karpenter can discover the relevant subnets](https://karpenter.sh/v0.6.1/aws/provisioning/#subnetselector) when provisioning a node for Spark jobs.


```terraform
# infra/main.tf
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.14"

  name = "${local.name}-vpc"
  cidr = local.vpc.cidr

  azs             = local.vpc.azs
  public_subnets  = [for k, v in local.vpc.azs : cidrsubnet(local.vpc.cidr, 3, k)]
  private_subnets = [for k, v in local.vpc.azs : cidrsubnet(local.vpc.cidr, 3, k + 3)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  create_igw           = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/elb"              = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/internal-elb"     = 1
    "karpenter.sh/discovery"              = local.name
  }

  tags = local.tags
}
```

### EKS Cluster

[Amazon EKS Blueprints for Terraform](https://aws-ia.github.io/terraform-aws-eks-blueprints/v4.7.0/) extends the [AWS EKS module](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/18.28.0), and it simplifies to create EKS clusters and Kubenetes add-ons. When it comes to EMR on EKS, it deploys the necessary resources to run EMR Spark jobs. Specifically it automates steps 4 to 7 of the [setup documentation](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/setting-up.html) and it is possible to configure multiple teams (namespaces) as well. In the module configuration, only one managed node group (_managed-ondemand_) is created, and it’ll be used to deploy all the critical add-ons. Note that Spark jobs will run in transient nodes, which are managed by Karpenter. Therefore, we don’t need to create node groups for them.

```terraform
# infra/main.tf
module "eks_blueprints" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=v4.7.0"

  cluster_name    = local.name
  cluster_version = local.eks.cluster_version

  # EKS network config
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols, recommended and required for Add-ons"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    egress_all = {
      description      = "Node all egress, recommended outbound traffic for Node groups"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
    ingress_cluster_to_node_all_traffic = {
      description                   = "Cluster API to Nodegroup all traffic, can be restricted further eg, spark-operator 8080..."
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  # EKS manage node groups
  managed_node_groups = {
    ondemand = {
      node_group_name        = "managed-ondemand"
      instance_types         = ["m5.xlarge"]
      subnet_ids             = module.vpc.private_subnets
      max_size               = 5
      min_size               = 1
      desired_size           = 1
      create_launch_template = true
      launch_template_os     = "amazonlinux2eks"
      update_config = [{
        max_unavailable_percentage = 30
      }]
    }
  }

  # EMR on EKS
  enable_emr_on_eks = true
  emr_on_eks_teams = {
    analytics = {
      namespace               = "analytics"
      job_execution_role      = "analytics-job-execution-role"
      additional_iam_policies = [aws_iam_policy.emr_on_eks.arn]
    }
  }

  tags = local.tags
}
```

### EMR Virtual Cluster

Terraform has the [EMR virtual cluster resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/emrcontainers_virtual_cluster) and the EKS cluster can be registered with the associating namespace (_analytics_). It’ll complete the last step of the [setup documentation](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/setting-up.html).


```terraform
# infra/main.tf
resource "aws_emrcontainers_virtual_cluster" "analytics" {
  name = "${module.eks_blueprints.eks_cluster_id}-analytics"

  container_provider {
    id   = module.eks_blueprints.eks_cluster_id
    type = "EKS"

    info {
      eks_info {
        namespace = "analytics"
      }
    }
  }
}
```

### Kubernetes Add-ons

The Blueprints include the [kubernetes-addons](https://github.com/aws-ia/terraform-aws-eks-blueprints/tree/main/modules/kubernetes-addons) module that simplifies deployment of [Amazon EKS add-ons](https://aws-ia.github.io/terraform-aws-eks-blueprints/v4.7.0/add-ons/managed-add-ons/) as well as [Kubernetes add-ons](https://aws-ia.github.io/terraform-aws-eks-blueprints/v4.7.0/add-ons/). For scaling Spark jobs in transient nodes, [Karpenter](https://aws-ia.github.io/terraform-aws-eks-blueprints/v4.7.0/add-ons/karpenter/) and [AWS Node Termination Handler](https://aws-ia.github.io/terraform-aws-eks-blueprints/v4.7.0/add-ons/aws-node-termination-handler/) add-ons will be used mainly.


```terraform
# infra/main.tf
module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=v4.7.0"

  eks_cluster_id       = module.eks_blueprints.eks_cluster_id
  eks_cluster_endpoint = module.eks_blueprints.eks_cluster_endpoint
  eks_oidc_provider    = module.eks_blueprints.oidc_provider
  eks_cluster_version  = module.eks_blueprints.eks_cluster_version

  # EKS add-ons
  enable_amazon_eks_vpc_cni    = true
  enable_amazon_eks_coredns    = true
  enable_amazon_eks_kube_proxy = true

  # K8s add-ons
  enable_coredns_autoscaler           = true
  enable_metrics_server               = true
  enable_cluster_autoscaler           = true
  enable_karpenter                    = true
  enable_aws_node_termination_handler = true

  tags = local.tags
}
```



### Karpenter

According to the [AWS News Blog](https://aws.amazon.com/blogs/aws/introducing-karpenter-an-open-source-high-performance-kubernetes-cluster-autoscaler/),


> _Karpenter is an open-source, flexible, high-performance Kubernetes cluster autoscaler built with AWS. It helps improve your application availability and cluster efficiency by rapidly launching right-sized compute resources in response to changing application load. Karpenter also provides just-in-time compute resources to meet your application’s needs and will soon automatically optimize a cluster’s compute resource footprint to reduce costs and improve performance._

Simply put, Karpeter adds nodes to handle unschedulable pods, schedules pods on those nodes, and removes the nodes when they are not needed. To configure Karpenter, we need to create [provisioners](https://karpenter.sh/v0.6.1/provisioner/) that define how Karpenter manages unschedulable pods and expired nodes. For Spark jobs, we can deploy separate provisioners for the driver and executor programs.


#### Spark Driver Provisioner

The _labels_ contain arbitrary key-value pairs. As shown later, we can add it to the _nodeSelector _field of the Spark pod template. Then Karpenter provisions a node (if not existing) as defined by this Provisioner object. The _requirements_ define which nodes to provision. Here 3 [well-known labels](https://kubernetes.io/docs/reference/labels-annotations-taints/) are specified -  availability zone, instance family and capacity type. The _provider_ section is specific to cloud providers and, for AWS, we need to indicate InstanceProfile, LaunchTemplate, SubnetSelector or SecurityGroupSelector. Here we’ll use a launch template that keeps the instance group and security group ids. SubnetSelector is added separately as it is not covered by the launch template. Recall that we added a tag to private subnets (_"karpenter.sh/discovery" = local.name_) and we can use it here so that Karpenter discovers the relevant subnets when provisioning a node.


```yaml
# infra/provisioners/spark-driver.yaml
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: spark-driver
spec:
  labels:
    type: karpenter
    provisioner: spark-driver
  ttlSecondsAfterEmpty: 30
  requirements:
    - key: "topology.kubernetes.io/zone"
      operator: In
      values: [${az}]
    - key: karpenter.k8s.aws/instance-family
      operator: In
      values: [m4, m5]
    - key: "karpenter.sh/capacity-type"
      operator: In
      values: ["on-demand"]
  limits:
    resources:
      cpu: "1000"
      memory: 1000Gi
  provider:
    launchTemplate: "karpenter-${cluster_name}"
    subnetSelector:
      karpenter.sh/discovery: ${cluster_name}
```

#### Spark Executor Provisioner

The executor provisioner configuration is similar except that it allows more instance family values and the capacity type value is changed into spot.


```yaml
# infra/provisioners/spark-executor.yaml
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: spark-executor
spec:
  labels:
    type: karpenter
    provisioner: spark-executor
  ttlSecondsAfterEmpty: 30
  requirements:
    - key: "topology.kubernetes.io/zone"
      operator: In
      values: [${az}]
    - key: karpenter.k8s.aws/instance-family
      operator: In
      values: [m4, m5, r4, r5]
    - key: "karpenter.sh/capacity-type"
      operator: In
      values: ["spot"]
  limits:
    resources:
      cpu: "1000"
      memory: 1000Gi
  provider:
    launchTemplate: "karpenter-${cluster_name}"
    subnetSelector:
      karpenter.sh/discovery: ${cluster_name}
```

#### Terraform Resources

As mentioned earlier, a launch template is created for the provisioners, and it includes the instance profile, security group ID and additional configuration. The provisioner resources are created from the YAML manifests. Note we only select a single available zone in order to save cost and improve performance of Spark jobs.


```terraform
# infra/main.tf
module "karpenter_launch_templates" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/launch-templates?ref=v4.7.0"

  eks_cluster_id = module.eks_blueprints.eks_cluster_id

  launch_template_config = {
    linux = {
      ami                    = data.aws_ami.eks.id
      launch_template_prefix = "karpenter"
      iam_instance_profile   = module.eks_blueprints.managed_node_group_iam_instance_profile_id[0]
      vpc_security_group_ids = [module.eks_blueprints.worker_node_security_group_id]
      block_device_mappings = [
        {
          device_name = "/dev/xvda"
          volume_type = "gp3"
          volume_size = 100
        }
      ]
    }
  }

  tags = merge(local.tags, { Name = "karpenter" })
}

# deploy spark provisioners for Karpenter autoscaler
data "kubectl_path_documents" "karpenter_provisioners" {
  pattern = "${path.module}/provisioners/spark*.yaml"
  vars = {
    az           = join(",", slice(local.vpc.azs, 0, 1))
    cluster_name = local.name
  }
}

resource "kubectl_manifest" "karpenter_provisioner" {
  for_each  = toset(data.kubectl_path_documents.karpenter_provisioners.documents)
  yaml_body = each.value

  depends_on = [module.eks_blueprints_kubernetes_addons]
}
```


Now we can deploy the infrastructure. Be patient until it completes.


## Spark Job

A test spark app and pod templates are uploaded to a S3 bucket. The spark app is for testing autoscaling, and it creates multiple parallel threads and waits for a few seconds - it is obtained from [EKS Workshop](https://www.eksworkshop.com/advanced/430_emr_on_eks/autoscaling/). The pod templates basically select the relevant provisioners for the driver and executor programs. Two Spark jobs will run with and without [Dynamic Resource Allocation (DRA)](https://spark.apache.org/docs/latest/job-scheduling.html#dynamic-resource-allocation). DRA is a Spark feature where the initial number of executors are spawned, and then it is increased until the maximum number of executors is met to process the pending tasks. Idle executors are terminated when there are no pending tasks. This feature is particularly useful if we are not sure how many executors are necessary.


```bash
## upload.sh
#!/usr/bin/env bash

# write test script
mkdir -p scripts/src
cat << EOF > scripts/src/threadsleep.py
import sys
from time import sleep
from pyspark.sql import SparkSession
spark = SparkSession.builder.appName("threadsleep").getOrCreate()
def sleep_for_x_seconds(x):sleep(x*20)
sc=spark.sparkContext
sc.parallelize(range(1,6), 5).foreach(sleep_for_x_seconds)
spark.stop()
EOF

# write pod templates
mkdir -p scripts/config
cat << EOF > scripts/config/driver-template.yaml
apiVersion: v1
kind: Pod
spec:
  nodeSelector:
    type: 'karpenter'
    provisioner: 'spark-driver'
  tolerations:
    - key: 'spark-driver'
      operator: 'Exists'
      effect: 'NoSchedule'
  containers:
  - name: spark-kubernetes-driver
EOF

cat << EOF > scripts/config/executor-template.yaml
apiVersion: v1
kind: Pod
spec:
  nodeSelector:
    type: 'karpenter'
    provisioner: 'spark-executor'
  tolerations:
    - key: 'spark-executor'
      operator: 'Exists'
      effect: 'NoSchedule'
  containers:
  - name: spark-kubernetes-executor
EOF

# sync to S3
DEFAULT_BUCKET_NAME=$(terraform -chdir=./infra output --raw default_bucket_name)
aws s3 sync . s3://$DEFAULT_BUCKET_NAME --exclude "*" --include "scripts/*"
```

### Without Dynamic Resource Allocation (DRA)

15 executors are configured to run for the Spark job without DRA. The application configuration is overridden to disable DRA and maps pod templates for the diver and executor programs.


```bash
export VIRTUAL_CLUSTER_ID=$(terraform -chdir=./infra output --raw emrcontainers_virtual_cluster_id)
export EMR_ROLE_ARN=$(terraform -chdir=./infra output --json emr_on_eks_role_arn | jq '.[0]' -r)
export DEFAULT_BUCKET_NAME=$(terraform -chdir=./infra output --raw default_bucket_name)
export AWS_REGION=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[0].[RegionName]' --output text)

## without DRA
aws emr-containers start-job-run \
--virtual-cluster-id $VIRTUAL_CLUSTER_ID \
--name threadsleep-karpenter-wo-dra \
--execution-role-arn $EMR_ROLE_ARN \
--release-label emr-6.7.0-latest \
--region $AWS_REGION \
--job-driver '{
    "sparkSubmitJobDriver": {
        "entryPoint": "s3://'${DEFAULT_BUCKET_NAME}'/scripts/src/threadsleep.py",
        "sparkSubmitParameters": "--conf spark.executor.instances=15 --conf spark.executor.memory=1G --conf spark.executor.cores=1 --conf spark.driver.cores=1"
        }
    }' \
--configuration-overrides '{
    "applicationConfiguration": [
      {
        "classification": "spark-defaults",
        "properties": {
          "spark.dynamicAllocation.enabled":"false",
          "spark.kubernetes.executor.deleteOnTermination": "true",
          "spark.kubernetes.driver.podTemplateFile":"s3://'${DEFAULT_BUCKET_NAME}'/scripts/config/driver-template.yaml",
          "spark.kubernetes.executor.podTemplateFile":"s3://'${DEFAULT_BUCKET_NAME}'/scripts/config/executor-template.yaml"
         }
      }
    ]
}'
```


As indicated earlier, Karpenter can provide just-in-time compute resources to meet the Spark job's requirements, and we see that 3 new nodes are added accordingly. Note that, unlike cluster autoscaler, Karpenter provision nodes without creating a node group.

![](karpenter-groupless-02.png#center)


Once the job completes, the new nodes are terminated as expected.

![](karpenter-groupless-03.png#center)


Below shows the event timeline of the Spark job. It adds all the 15 executors regardless of whether there are pending tasks or not. The DRA feature of Spark can be beneficial in this situation, and it’ll be discussed in the next section.

![](event-timeline-wo-dra.png#center)


### With Dynamic Resource Allocation (DRA)

Here the initial number of executors is set to 1. With DRA enabled, the driver is expected to scale up the executors until it reaches the maximum number of executors if there are pending tasks.  


```bash
export VIRTUAL_CLUSTER_ID=$(terraform -chdir=./infra output --raw emrcontainers_virtual_cluster_id)
export EMR_ROLE_ARN=$(terraform -chdir=./infra output --json emr_on_eks_role_arn | jq '.[0]' -r)
export DEFAULT_BUCKET_NAME=$(terraform -chdir=./infra output --raw default_bucket_name)
export AWS_REGION=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[0].[RegionName]' --output text)

## with DRA
aws emr-containers start-job-run \
--virtual-cluster-id $VIRTUAL_CLUSTER_ID \
--name threadsleep-karpenter-w-dra \
--execution-role-arn $EMR_ROLE_ARN \
--release-label emr-6.7.0-latest \
--region $AWS_REGION \
--job-driver '{
    "sparkSubmitJobDriver": {
        "entryPoint": "s3://'${DEFAULT_BUCKET_NAME}'/scripts/src/threadsleep.py",
        "sparkSubmitParameters": "--conf spark.executor.instances=1 --conf spark.executor.memory=1G --conf spark.executor.cores=1 --conf spark.driver.cores=1"
        }
    }' \
--configuration-overrides '{
    "applicationConfiguration": [
      {
        "classification": "spark-defaults",
        "properties": {
          "spark.dynamicAllocation.enabled":"true",
          "spark.dynamicAllocation.shuffleTracking.enabled":"true",
          "spark.dynamicAllocation.minExecutors":"1",
          "spark.dynamicAllocation.maxExecutors":"10",
          "spark.dynamicAllocation.initialExecutors":"1",
          "spark.dynamicAllocation.schedulerBacklogTimeout": "1s",
          "spark.dynamicAllocation.executorIdleTimeout": "5s",
          "spark.kubernetes.driver.podTemplateFile":"s3://'${DEFAULT_BUCKET_NAME}'/scripts/config/driver-template.yaml",
          "spark.kubernetes.executor.podTemplateFile":"s3://'${DEFAULT_BUCKET_NAME}'/scripts/config/executor-template.yaml"
         }
      }
    ]
}'
```


As expected, the executors are added dynamically and removed subsequently as they are not needed.

![](event-timeline-w-dra.png#center)


## Summary

In this post, it is discussed how to provision and manage Spark jobs on EMR on EKS with Terraform. Amazon EKS Blueprints for Terraform is used for provisioning EKS, EMR virtual cluster and related resources. Also, Karpenter is used to manage Spark job autoscaling and two Spark jobs with and without Dynamic Resource Allocation (DRA) are used for comparison. It is found that Karpenter manages transient nodes for Spark jobs to meet their scaling requirements effectively.
