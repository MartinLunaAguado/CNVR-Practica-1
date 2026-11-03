# =============================================================================
# outputs.tf
# -----------------------------------------------------------------------------
# Información útil tras el "terraform apply" (consultable con "terraform output").
# =============================================================================

# Lista de Pods web (consultada después de crear el Deployment)
data "kubernetes_resources" "web_pods" {
  api_version    = "v1"
  kind           = "Pod"
  namespace      = var.namespace
  label_selector = "app=${local.web_labels.app}"
  depends_on     = [kubernetes_deployment_v1.web]
}

output "ruta_ingress" {
  description = "Ruta HTTP publicada en el Ingress"
  value       = local.ruta_ingress
}

output "web_pod_names" {
  description = "Nombres de los Pods web"
  value       = [for p in data.kubernetes_resources.web_pods.objects : p.metadata.name]
}

# IP de cada Pod web en la VLAN, extraída de la anotación que escribe Multus.
# Si sale "pendiente", ejecutad: terraform apply -refresh-only
output "web_pods_ip_vlan" {
  description = "IP de la interfaz VLAN (net1) de cada Pod web"
  value = {
    for p in data.kubernetes_resources.web_pods.objects :
    p.metadata.name => try(
      [for n in jsondecode(p.metadata.annotations["k8s.v1.cni.cncf.io/network-status"]) :
      n.ips[0] if try(n.interface, "") == "net1"][0],
      "pendiente"
    )
  }
}

output "admin_ip_vlan" {
  description = "IP fija del admin en la VLAN"
  value       = var.vlan_admin_ip
}

output "ssh_admin" {
  description = "Comando para entrar al admin desde el host"
  value       = "ssh -i keys/host_key -p ${var.admin_node_port} root@<IP_${var.admin_node}>"
}
