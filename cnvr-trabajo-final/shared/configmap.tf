# =============================================================================
# configmap.tf
# =============================================================================

# -----------------------------------------------------------------------------
# (Apartado 3, paso 1) ConfigMap con la PLANTILLA index.html.
# La plantilla contiene el marcador __POD_NAME__, que el initContainer del
# Deployment sustituye por el nombre real del Pod (y, como extra, __NODE_NAME__
# y __POD_IP__).
#
# templatefile() rellena ${grupo} cuando se ejecuta Terraform. Los marcadores
# __XXX__ no son sintaxis de Terraform, así que llegan intactos al ConfigMap.
# -----------------------------------------------------------------------------
resource "kubernetes_config_map_v1" "plantilla_web" {
  metadata {
    name      = "plantilla-web"
    namespace = var.namespace
  }
  data = {
    "index.html" = templatefile("${path.module}/html/index.html.tpl", {
      grupo = var.grupo
    })
  }
}

# -----------------------------------------------------------------------------
# Configuración del CLIENTE SSH del admin (~/.ssh/config). No es un dato
# secreto, por eso va en un ConfigMap y no en un Secret.
#   * "ssh bbdd" y "ssh logs" entran como root en los contenedores LXC.
#   * Cualquier otro destino (los servidores web) usa el usuario webuser.
#   * No se guardan las claves de host: los Pods son efímeros y al recrearse
#     pueden reutilizar una IP con otra clave de host, lo que bloquearía el
#     acceso con el aviso "REMOTE HOST IDENTIFICATION HAS CHANGED".
# En ssh_config gana el primer valor que coincide, por eso "Host *" va al final.
# -----------------------------------------------------------------------------
resource "kubernetes_config_map_v1" "ssh_config_admin" {
  metadata {
    name      = "ssh-config-admin"
    namespace = var.namespace
  }
  data = {
    "config" = <<-EOT
      Host bbdd
        HostName ${var.bbdd_ip}
      Host logs
        HostName ${var.logs_ip}
      Host bbdd logs ${var.bbdd_ip} ${var.logs_ip}
        User root
      Host *
        User ${var.usuario_web}
        IdentityFile ${local.ssh_dir_admin}/id_rsa
        StrictHostKeyChecking no
        UserKnownHostsFile /dev/null
        LogLevel ERROR
    EOT
  }
}
