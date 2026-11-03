# =============================================================================
# multus.tf  (Apartado 2, punto 2 del enunciado)
# -----------------------------------------------------------------------------
# NetworkAttachmentDefinition (NAD): recurso personalizado (CRD) de Multus que
# describe una red ADICIONAL para los Pods. El proveedor de Terraform no tiene
# un recurso específico para él, así que usamos kubernetes_manifest, que admite
# cualquier objeto de Kubernetes escrito en HCL.
#
# Ambas NAD usan el plugin "macvlan" sobre la subinterfaz VLAN de los workers
# (p.ej. eth2.100). Así cada Pod recibe una interfaz "net1" con MAC propia que
# sale directamente a la VLAN, donde también están los contenedores LXC.
#
#  - vlan-web   : IPAM "whereabouts" -> reparte IPs de un rango a TODO el
#                 clúster sin repetir (host-local repetiría IPs entre nodos).
#  - vlan-admin : IPAM "static"      -> IP fija para el admin (un único Pod).
#
# IMPORTANTE: kubernetes_manifest necesita que la CRD de Multus exista ya en el
# clúster durante "terraform plan".
# =============================================================================

resource "kubernetes_manifest" "nad_vlan_web" {
  manifest = {
    apiVersion = "k8s.cni.cncf.io/v1"
    kind       = "NetworkAttachmentDefinition"
    metadata = {
      name      = "vlan-web"
      namespace = var.namespace
    }
    spec = {
      config = jsonencode({
        cniVersion = "0.3.1"
        name       = "vlan-web"
        type       = "macvlan"
        master     = local.vlan_if
        mode       = "bridge"
        ipam = {
          type        = "whereabouts"
          range       = var.vlan_cidr
          range_start = var.vlan_web_range_start
          range_end   = var.vlan_web_range_end
        }
      })
    }
  }
}

resource "kubernetes_manifest" "nad_vlan_admin" {
  manifest = {
    apiVersion = "k8s.cni.cncf.io/v1"
    kind       = "NetworkAttachmentDefinition"
    metadata = {
      name      = "vlan-admin"
      namespace = var.namespace
    }
    spec = {
      config = jsonencode({
        cniVersion = "0.3.1"
        name       = "vlan-admin"
        type       = "macvlan"
        master     = local.vlan_if
        mode       = "bridge"
        ipam = {
          type      = "static"
          addresses = [{ address = var.vlan_admin_ip }]
        }
      })
    }
  }
}
