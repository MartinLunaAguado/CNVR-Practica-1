# =============================================================================
# web-deployment.tf  (Apartados 2 y 3 del enunciado)
# -----------------------------------------------------------------------------
# Deployment con los 3 Pods de servidores web (S1, S2, S3 de la Figura 1).
#
# Cada Pod tiene:
#   * Una interfaz extra "net1" en la VLAN (anotación de Multus -> NAD vlan-web).
#   * initContainer "genera-index" (OPCIÓN B del apartado 3): lee la plantilla
#     del ConfigMap, sustituye __POD_NAME__ por el nombre del Pod y escribe el
#     resultado en un volumen emptyDir compartido con Nginx.
#   * initContainer "prepara-ssh": copia la clave pública autorizada (Secret)
#     a /root/.ssh con los permisos que exige sshd (700 dir / 600 fichero).
#   * Contenedor principal "web" (imagen proporcionada: Nginx + SSH).
#
# Volúmenes:
#   plantilla (ConfigMap, SOLO LECTURA) | html (emptyDir, ESCRITURA)
#   ssh-secret (Secret, solo lectura)   | ssh-dir (emptyDir -> /root/.ssh)
# =============================================================================

resource "kubernetes_deployment_v1" "web" {
  metadata {
    name      = "web"
    namespace = var.namespace
    labels    = local.web_labels
  }

  spec {
    replicas = var.num_replicas

    selector {
      match_labels = local.web_labels
    }

    template {
      metadata {
        labels = local.web_labels
        annotations = {
          # Multus: añade al Pod una interfaz (net1) de la red "vlan-web".
          # Referenciar el recurso crea la dependencia: primero la NAD.
          "k8s.v1.cni.cncf.io/networks" = kubernetes_manifest.nad_vlan_web.manifest.metadata.name
        }
      }

      spec {
        # --------------------------------------------- initContainer 1: HTML --
        init_container {
          name    = "genera-index"
          image   = var.imagen_init
          command = ["sh", "-c"]
          args = [<<-EOT
            sed -e "s/__POD_NAME__/$POD_NAME/g" \
                -e "s/__NODE_NAME__/$NODE_NAME/g" \
                -e "s/__POD_IP__/$POD_IP/g" \
                /plantilla/index.html > /html/index.html
            echo "index.html generado para $POD_NAME"
          EOT
          ]

          # Downward API: Kubernetes inyecta el nombre del Pod, del nodo y la IP
          env {
            name = "POD_NAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }
          env {
            name = "NODE_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }
          env {
            name = "POD_IP"
            value_from {
              field_ref {
                field_path = "status.podIP"
              }
            }
          }

          volume_mount {
            name       = "plantilla"
            mount_path = "/plantilla"
            read_only  = true
          }
          volume_mount {
            name       = "html"
            mount_path = "/html"
          }
        }

        # ---------------------------------------------- initContainer 2: SSH --
        init_container {
          name    = "prepara-ssh"
          image   = var.imagen_init
          command = ["sh", "-c"]
          args = [<<-EOT
            cp /ssh-secret/authorized_keys /ssh/authorized_keys
            chmod 700 /ssh
            chmod 600 /ssh/authorized_keys
          EOT
          ]
          volume_mount {
            name       = "ssh-secret"
            mount_path = "/ssh-secret"
            read_only  = true
          }
          volume_mount {
            name       = "ssh-dir"
            mount_path = "/ssh"
          }
        }

        # ------------------------------------------- Contenedor principal -----
        container {
          name  = "web"
          image = var.imagen_web

          port {
            name           = "http"
            container_port = 80
          }
          port {
            name           = "ssh"
            container_port = 22
          }

          volume_mount {
            name       = "html"
            mount_path = var.web_root
          }
          volume_mount {
            name       = "ssh-dir"
            mount_path = "/root/.ssh"
          }
        }

        # ------------------------------------------------------- Volúmenes ----
        volume {
          name = "plantilla"
          config_map {
            name = kubernetes_config_map_v1.plantilla_web.metadata[0].name
          }
        }
        volume {
          name = "html"
          empty_dir {}
        }
        volume {
          name = "ssh-secret"
          secret {
            secret_name  = kubernetes_secret_v1.ssh_web_autorizadas.metadata[0].name
            default_mode = "0400"
          }
        }
        volume {
          name = "ssh-dir"
          empty_dir {}
        }
      }
    }
  }
}
