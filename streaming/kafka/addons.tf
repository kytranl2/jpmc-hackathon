#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------

module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.20"

  role_name_prefix = "${module.eks.cluster_name}-ebs-csi-driver-"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

#---------------------------------------------------------------
# IRSA for VPC CNI
#---------------------------------------------------------------

module "vpc_cni_ipv4_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.20"

  role_name_prefix = "${module.eks.cluster_name}-vpc-cni-ipv4"

  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }

  tags = local.tags
}

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.0"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------
  # Amazon EKS Managed Add-ons
  #---------------------------------------
  eks_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
    vpc-cni = {
      service_account_role_arn = module.vpc_cni_ipv4_irsa.iam_role_arn
    }
    coredns    = {}
    kube-proxy = {}
  }

  #---------------------------------------
  # Kubernetes Add-ons
  #---------------------------------------

  #---------------------------------------------------------------
  # CoreDNS Autoscaler helps to scale for large EKS Clusters
  #   Further tuning for CoreDNS is to leverage NodeLocal DNSCache -> https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/
  #---------------------------------------------------------------
  enable_cluster_proportional_autoscaler = true
  cluster_proportional_autoscaler = {
    timeout = "300"
    values = [templatefile("${path.module}/helm-values/coredns-autoscaler-values.yaml", {
      target = "deployment/coredns"
    })]
    description = "Cluster Proportional Autoscaler for CoreDNS Service"
  }

  #---------------------------------------
  # Metrics Server
  #---------------------------------------
  enable_metrics_server = true
  metrics_server = {
    timeout = "300"
    values = [templatefile("${path.module}/helm-values/metrics-server-values.yaml", {
      operating_system = "linux"
      node_group_type  = "core"
    })]
  }

  #---------------------------------------
  # Cluster Autoscaler
  #---------------------------------------
  enable_cluster_autoscaler = true
  cluster_autoscaler = {
    timeout     = "300"
    create_role = true
    values = [templatefile("${path.module}/helm-values/cluster-autoscaler-values.yaml", {
      aws_region     = local.region,
      eks_cluster_id = module.eks.cluster_name
    })]
  }

  #---------------------------------------
  # Prommetheus and Grafana stack
  #---------------------------------------
  #---------------------------------------------------------------
  # Install Kafka Montoring Stack with Prometheus and Grafana
  # 1- Grafana port-forward `kubectl port-forward svc/kube-prometheus-stack-grafana 8080:80 -n kube-prometheus-stack`
  # 2- Grafana Admin user: admin
  # 3- Get admin user password: `kubectl get secret kube-prometheus-stack-grafana -n kube-prometheus-stack -o jsonpath="{.data.admin-password}" | base64 --decode ; echo`
  #---------------------------------------------------------------
  enable_kube_prometheus_stack = true
  kube_prometheus_stack = {
    values = [templatefile("${path.module}/helm-values/prom-grafana-values.yaml", {})]
  }

  tags = local.tags
}

#---------------------------------------------------------------
# Data on EKS Kubernetes Addons
#---------------------------------------------------------------
# NOTE: This module will be moved to a dedicated repo and the source will be changed accordingly.
module "kubernetes_data_addons" {
  # Please note that local source will be replaced once the below repo is public
  # source = "https://github.com/aws-ia/terraform-aws-kubernetes-data-addons"
  source = "../../workshop/modules/terraform-aws-eks-data-addons"

  oidc_provider_arn = module.eks.oidc_provider_arn
  #---------------------------------------------------------------
  # Strimzi Kafka Add-on
  #---------------------------------------------------------------
  enable_strimzi_kafka_operator = true
  strimzi_kafka_operator_helm_config = {
    values = [templatefile("${path.module}/helm-values/strimzi-kafka-values.yaml", {
      operating_system = "linux"
      node_group_type  = "core"
    })]
  }
}

#---------------------------------------------------------------
# Install Kafka cluster
# NOTE: Kafka Zookeeper and Broker pod creation may to 2 to 3 mins
#---------------------------------------------------------------

resource "kubernetes_namespace" "kafka_namespace" {
  metadata {
    name = local.kafka_namespace
  }

  depends_on = [module.eks.cluster_name]
}

data "kubectl_path_documents" "kafka_cluster" {
  pattern = "${path.module}/kafka-manifests/kafka-cluster.yaml"
}

resource "kubectl_manifest" "kafka_cluster" {
  for_each  = toset(data.kubectl_path_documents.kafka_cluster.documents)
  yaml_body = each.value

  depends_on = [module.kubernetes_data_addons]
}

#---------------------------------------------------------------
# Deploy Strimzi Kafka and Zookeeper dashboards in Grafana
#---------------------------------------------------------------

data "kubectl_path_documents" "podmonitor_metrics" {
  pattern = "${path.module}/monitoring-manifests/podmonitor-*.yaml"
}

resource "kubectl_manifest" "podmonitor_metrics" {
  for_each  = toset(data.kubectl_path_documents.podmonitor_metrics.documents)
  yaml_body = each.value

  depends_on = [module.eks_blueprints_addons]
}

data "kubectl_path_documents" "grafana_strimzi_dashboard" {
  pattern = "${path.module}/monitoring-manifests/grafana-strimzi-*-dashboard.yaml"
}

resource "kubectl_manifest" "grafana_strimzi_dashboard" {
  for_each  = toset(data.kubectl_path_documents.grafana_strimzi_dashboard.documents)
  yaml_body = each.value

  depends_on = [module.eks_blueprints_addons]
}