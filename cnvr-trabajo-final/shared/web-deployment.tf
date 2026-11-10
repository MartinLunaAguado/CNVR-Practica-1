# =============================================================================
# web-deployment.tf  (Apartados 2 y 3 del enunciado)
# -----------------------------------------------------------------------------
# Deployment con los 3 Pods de servidores web (S1, S2 y S3 de la Figura 1).
#
# Cada Pod tiene:
#   * Interfaz extra "net1" en la VLAN (anotación de Multus -> NAD vlan-web).
#   * initContainer "genera-index" (OPCIÓN B del apartado 3): lee la plantilla
#     del ConfigMap, sustituye __POD_NAME__ por el nombre del Pod y escribe el
#     resultado en un volumen emptyDir compartido con Nginx.
#   * Contenedor "web" (imagen dgsgiros/nginx-ssh: Nginx + servidor SSH).
#
# Volúmenes:
#   plantilla            ConfigMap, SOLO LECTURA   -> lo lee el initContainer
#   html                 emptyDir, ESCRITURA       -> initContainer escribe, Nginx sirve
#   ssh-authorized-keys  Secret (clave pública del admin) -> authorized_keys
#
# Claves SSH (apartado 2, paso 5): el Secret se monta como FICHERO en
# /home/webuser/.ssh/authorized_keys.
#   - mode 0440 + fsGroup 1000: el fichero queda root:1000 r--r-----, legible
#     por webuser (GID 1000) y no modificable, que es lo que exige sshd.
#   - sub_path: se monta solo el fichero, no todo el volumen. Si se montase el
#     volumen entero sobre ~/.ssh, ese directorio quedaría con permisos de
#     escritura para todos y sshd (StrictModes) rechazaría la clave.
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
          # Multus: añade al Pod una interfaz (net1) conectada a la red "vlan-web".
          # Al referenciar el recurso, Terraform crea primero la NAD.
          "k8s.v1.cni.cncf.io/networks" = kubernetes_manifest.nad_vlan_web.manifest.metadata.name

          # Huella de la plantilla: si cambia el index.html del ConfigMap, cambia
          # esta anotación y el Deployment recrea los Pods (el initContainer
          # solo se ejecuta al arrancar el Pod).
          "cnvr.upm/plantilla-sha256" = sha256(kubernetes_config_map_v1.plantilla_web.data["index.html"])
        }
      }

      spec {
        # Los volúmenes se asocian al grupo 1000 (el de webuser)
        security_context {
          fs_group = var.ssh_gid
        }

        # ------------------------------------ initContainer: genera la página --
        init_container {
          name    = "genera-index"
          image   = var.imagen_init
          command = ["sh", "-c"]
          args = [<<-EOT
            sed -e "s/__POD_NAME__/$POD_NAME/g" \
                -e "s/__NODE_NAME__/$NODE_NAME/g" \
                -e "s/__POD_IP__/$POD_IP/g" \
                /plantilla/index.html > /html/index.html
            chmod 644 /html/index.html
            echo "index.html generado para $POD_NAME"
          EOT
          ]

          # Downward API: Kubernetes inyecta el nombre del Pod, el nodo y la IP
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

          # El Pod no recibe tráfico del Service hasta que Nginx responde
          readiness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 2
            period_seconds        = 5
          }

          volume_mount {
            name       = "html"
            mount_path = var.web_root
          }
          volume_mount {
            name       = "ssh-authorized-keys"
            mount_path = "${local.ssh_dir_web}/authorized_keys"
            sub_path   = "authorized_keys"
            read_only  = true
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
          name = "ssh-authorized-keys"
          secret {
            secret_name  = kubernetes_secret_v1.ssh_web_autorizadas.metadata[0].name
            default_mode = "0440"
            items {
              key  = "authorized_keys"
              path = "authorized_keys"
              mode = "0440"
            }
          }
        }
      }
    }
  }
}
