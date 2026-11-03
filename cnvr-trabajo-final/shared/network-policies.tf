# =============================================================================
# network-policies.tf  (Apartado 5 del enunciado)
# -----------------------------------------------------------------------------
# Recordatorios (P1.4, apartado 3.3):
#   * Las NetworkPolicy son ADITIVAS: lo permitido es la unión de todas las
#     políticas que seleccionan a un Pod.
#   * Son STATEFUL: si se permite el inicio de una conexión, sus respuestas
#     vuelven sin necesitar otra regla.
#   * Calico las aplica sobre la interfaz principal del Pod (eth0). La interfaz
#     Multus de la VLAN (net1) NO pasa por Calico, por eso el tráfico admin ->
#     web / BBDD / logs por la VLAN no se ve afectado por estas políticas.
#   * El puerto que se indica es el del POD (80, 22), no el del Service.
# =============================================================================

# 1) Denegación por defecto: todo el tráfico de entrada y salida de todos los
#    Pods del namespace queda bloqueado (no hay reglas ingress/egress).
resource "kubernetes_network_policy_v1" "default_deny_all" {
  metadata {
    name      = "default-deny-all"
    namespace = var.namespace
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

# 2) Servidores web: solo admiten conexiones al puerto 80 desde los Pods del
#    Ingress Controller del namespace ingress-nginx.
#    namespace_selector y pod_selector dentro del MISMO bloque "from" = AND
#    (Pods con esas etiquetas Y en ese namespace).
resource "kubernetes_network_policy_v1" "web_desde_ingress" {
  metadata {
    name      = "web-allow-from-ingress-nginx"
    namespace = var.namespace
  }
  spec {
    pod_selector {
      match_labels = local.web_labels
    }
    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = var.ingress_controller_namespace
          }
        }
        pod_selector {
          match_labels = var.ingress_controller_labels
        }
      }
      ports {
        protocol = "TCP"
        port     = "80"
      }
    }
  }
}

# 3) Servidor admin: solo SSH (TCP/22) desde la IP del host (ipBlock /32).
resource "kubernetes_network_policy_v1" "admin_ssh_desde_host" {
  metadata {
    name      = "admin-allow-ssh-from-host"
    namespace = var.namespace
  }
  spec {
    pod_selector {
      match_labels = local.admin_labels
    }
    policy_types = ["Ingress"]

    ingress {
      from {
        ip_block {
          cidr = "${var.host_ip}/32"
        }
      }
      ports {
        protocol = "TCP"
        port     = "22"
      }
    }
  }
}
