# =============================================================================
# admin-pod.tf  (Apartados 2 y 5.3 del enunciado)
# -----------------------------------------------------------------------------
# Pod del servidor de administración (imagen dgsgiros/admin-ssh, usuario
# adminuser).
#
#   * nodeSelector -> se ejecuta SIEMPRE en k8s-worker1. Junto con
#     externalTrafficPolicy: Local en su Service, el tráfico que llega a
#     worker1:nodePort se entrega al Pod sin cambiar la IP origen (sin SNAT),
#     y la NetworkPolicy con ipBlock puede filtrar por la IP del host.
#   * Interfaz extra en la VLAN con IP fija (NAD vlan-admin).
#   * fsGroup 1000 -> los ficheros de los Secrets pertenecen al grupo de
#     adminuser, que puede leerlos con los permisos de grupo (0440).
#   * Tres ficheros montados en /home/adminuser/.ssh, cada uno de su recurso:
#       id_rsa           Secret ssh-admin-private-key      (Par I, privada)
#       authorized_keys  Secret ssh-admin-authorized-keys  (Par II, pública)
#       config           ConfigMap ssh-config-admin        (cliente SSH)
#
# Nota sobre la clave privada: queda como root:1000 con modo 0440. El cliente
# ssh solo exige "permisos privados" (0600) cuando el fichero pertenece al
# usuario que lo usa; como aquí el dueño es root, adminuser puede usarla.
# Por el mismo motivo NO funciona ejecutando ssh como root (kubectl exec):
# hay que entrar como adminuser.
# =============================================================================

resource "kubernetes_pod_v1" "admin" {
  metadata {
    name      = "admin"
    namespace = var.namespace
    labels    = local.admin_labels
    annotations = {
      "k8s.v1.cni.cncf.io/networks" = kubernetes_manifest.nad_vlan_admin.manifest.metadata.name
    }
  }

  spec {
    node_selector = {
      "kubernetes.io/hostname" = var.admin_node
    }

    security_context {
      fs_group = var.ssh_gid
    }

    container {
      name  = "admin"
      image = var.imagen_admin

      port {
        name           = "ssh"
        container_port = 22
      }

      volume_mount {
        name       = "ssh-private-key"
        mount_path = "${local.ssh_dir_admin}/id_rsa"
        sub_path   = "id_rsa"
        read_only  = true
      }
      volume_mount {
        name       = "ssh-authorized-keys"
        mount_path = "${local.ssh_dir_admin}/authorized_keys"
        sub_path   = "authorized_keys"
        read_only  = true
      }
      volume_mount {
        name       = "ssh-config"
        mount_path = "${local.ssh_dir_admin}/config"
        sub_path   = "config"
        read_only  = true
      }
    }

    volume {
      name = "ssh-private-key"
      secret {
        secret_name  = kubernetes_secret_v1.ssh_admin_privada.metadata[0].name
        default_mode = "0440"
        items {
          key  = "id_rsa"
          path = "id_rsa"
          mode = "0440"
        }
      }
    }
    volume {
      name = "ssh-authorized-keys"
      secret {
        secret_name  = kubernetes_secret_v1.ssh_admin_autorizadas.metadata[0].name
        default_mode = "0440"
        items {
          key  = "authorized_keys"
          path = "authorized_keys"
          mode = "0440"
        }
      }
    }
    volume {
      name = "ssh-config"
      config_map {
        name         = kubernetes_config_map_v1.ssh_config_admin.metadata[0].name
        default_mode = "0444"
      }
    }
  }
}
