# =============================================================================
# network-policies.tf  (Apartado 5 del enunciado)
# -----------------------------------------------------------------------------
# Recordatorios (práctica 1.4, apartado 3.3):
#   * Las NetworkPolicy son ADITIVAS: lo permitido es la unión de todas las
#     políticas que seleccionan a un Pod.
#   * Son STATEFUL: si se permite el inicio de una conexión, sus respuestas
#     vuelven sin necesitar otra regla.
#   * Calico las aplica en la interfaz principal del Pod (eth0). La interfaz
#     de Multus en la VLAN (net1) NO pasa por Calico: el tráfico admin -> web /
#     BBDD / logs por la VLAN no se ve afectado por estas políticas.
#   * El puerto que se indica es el del POD (80, 22), no el del Service.
# =============================================================================

# 1) Denegación por defecto: sin reglas ingress/egress, todo el tráfico de
#    entrada y de salida de todos los Pods del namespace queda bloqueado.
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
#    namespace_selector y pod_selector en el MISMO bloque "from" = Y lógico
#    (Pods con esas etiquetas Y que están en ese namespace).
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

# -----------------------------------------------------------------------------
# OPCIONAL (mantenimiento): política temporal que permite la SALIDA de los
# Pods. Solo existe si se aplica con -var="permitir_salida_temporal=true";
# sirve para instalar paquetes con apt (p.ej. el cliente de MariaDB) y se
# elimina volviendo a aplicar sin la variable. Demuestra que las políticas son
# aditivas: no se toca default-deny-all, se añade un permiso.
# -----------------------------------------------------------------------------
resource "kubernetes_network_policy_v1" "salida_temporal" {
  count = var.permitir_salida_temporal ? 1 : 0

  metadata {
    name      = "temporal-allow-egress"
    namespace = var.namespace
  }
  spec {
    pod_selector {}
    policy_types = ["Egress"]
    egress {} # una regla vacía = permitir toda la salida
  }
}
