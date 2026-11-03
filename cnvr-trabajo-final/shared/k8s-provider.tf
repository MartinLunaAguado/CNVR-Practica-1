# =============================================================================
# k8s-provider.tf
# -----------------------------------------------------------------------------
# Declara el proveedor de Kubernetes para Terraform y cómo conectarse al
# clúster. Es el mismo fichero de la práctica 1.4 (apartado 3.1).
#
# El fichero ~/.kube/config de la máquina "terraform" lo dejan preparado los
# scripts del escenario: ./bin/get-master-kubeconf y ./bin/set-terraform-kubeconf
# =============================================================================

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.23.0"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}
