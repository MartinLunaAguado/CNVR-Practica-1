# =============================================================================
# k8s-provider.tf
# -----------------------------------------------------------------------------
# Proveedor de Kubernetes para Terraform (misma versión que en la práctica 1.4).
#
# El fichero ~/.kube/config de la máquina "terraform" lo dejan preparado los
# scripts del escenario: ./bin/get-master-kubeconf y ./bin/set-terraform-kubeconf
#
# ignore_annotations: Calico y Multus escriben anotaciones en los Pods cuando
# arrancan (IP asignada, estado de las redes...). Si no se ignoran, Terraform
# las ve como "cambios hechos fuera" en el Pod admin y querría borrarlas en
# cada apply. Con esto, un segundo "terraform apply" dice "No changes".
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

  ignore_annotations = [
    "cni\\.projectcalico\\.org\\/.*",
    "k8s\\.v1\\.cni\\.cncf\\.io\\/network-status",
    "k8s\\.v1\\.cni\\.cncf\\.io\\/networks-status",
  ]
}
