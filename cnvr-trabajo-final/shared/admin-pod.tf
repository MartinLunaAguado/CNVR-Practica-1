# =============================================================================
# admin-pod.tf  (Apartados 2 y 5.3 del enunciado)
# -----------------------------------------------------------------------------
# Pod del servidor de administración.
#   * nodeSelector -> se ejecuta SIEMPRE en k8s-worker1. Junto con
#     externalTrafficPolicy: Local en su Service, garantiza que el tráfico que
#     llega a worker1:nodePort se entrega al Pod sin SNAT (se conserva la IP
#     del host y la NetworkPolicy con ipBlock puede filtrarla).
#   * Interfaz extra en la VLAN con IP fija (NAD vlan-admin).
#   * initContainer que coloca en /root/.ssh:
#       - id_ed25519 (clave privada para entrar a web y LXC)
#       - config     (cliente SSH)
#       - authorized_keys (clave pública del host, para que el host entre)
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

    init_container {
      name    = "prepara-ssh"
      image   = var.imagen_init
      command = ["sh", "-c"]
      args = [<<-EOT
        cp /claves/id_ed25519 /claves/id_ed25519.pub /claves/config /ssh/
        cp /autorizadas/authorized_keys /ssh/authorized_keys
        chmod 700 /ssh
        chmod 600 /ssh/id_ed25519 /ssh/authorized_keys /ssh/config
        chmod 644 /ssh/id_ed25519.pub
      EOT
      ]
      volume_mount {
        name       = "claves"
        mount_path = "/claves"
        read_only  = true
      }
      volume_mount {
        name       = "autorizadas"
        mount_path = "/autorizadas"
        read_only  = true
      }
      volume_mount {
        name       = "ssh-dir"
        mount_path = "/ssh"
      }
    }

    container {
      name  = "admin"
      image = var.imagen_admin

      port {
        name           = "ssh"
        container_port = 22
      }

      volume_mount {
        name       = "ssh-dir"
        mount_path = "/root/.ssh"
      }
    }

    volume {
      name = "claves"
      secret {
        secret_name  = kubernetes_secret_v1.ssh_admin_privada.metadata[0].name
        default_mode = "0400"
      }
    }
    volume {
      name = "autorizadas"
      secret {
        secret_name  = kubernetes_secret_v1.ssh_admin_autorizadas.metadata[0].name
        default_mode = "0400"
      }
    }
    volume {
      name = "ssh-dir"
      empty_dir {}
    }
  }
}
