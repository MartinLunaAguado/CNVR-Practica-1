# =============================================================================
# secrets.tf  (Apartado 2, punto 5 del enunciado)
# -----------------------------------------------------------------------------
# Distribuimos las claves SSH a los Pods mediante Secrets.
#
# Se usan DOS pares de claves (se generan con scripts/00-generar-claves.sh):
#   - admin_key / admin_key.pub : el admin se conecta con la PRIVADA a los
#     servidores web y a los LXC, que tienen la PÚBLICA en authorized_keys.
#   - host_key  / host_key.pub  : el host (vuestro PC del laboratorio) entra al
#     admin; el admin tiene la PÚBLICA del host en authorized_keys.
#
# Nota: en el campo "data" se pone el contenido en claro; el proveedor lo
# codifica en base64 automáticamente al crear el Secret.
# =============================================================================

# Clave PRIVADA (y pública) que usará el servidor de administración
resource "kubernetes_secret_v1" "ssh_admin_privada" {
  metadata {
    name      = "ssh-admin-privada"
    namespace = var.namespace
  }
  type = "Opaque"
  data = {
    "id_ed25519"     = file("${path.module}/${var.ssh_admin_private_key}")
    "id_ed25519.pub" = file("${path.module}/${var.ssh_admin_public_key}")
    # Configuración del cliente SSH del admin: no preguntar "yes/no" la primera vez
    "config" = <<-EOT
      Host *
        User root
        IdentityFile /root/.ssh/id_ed25519
        StrictHostKeyChecking accept-new
    EOT
  }
}

# Clave PÚBLICA del admin -> authorized_keys de los servidores web
resource "kubernetes_secret_v1" "ssh_web_autorizadas" {
  metadata {
    name      = "ssh-web-authorized-keys"
    namespace = var.namespace
  }
  type = "Opaque"
  data = {
    "authorized_keys" = file("${path.module}/${var.ssh_admin_public_key}")
  }
}

# Clave PÚBLICA del host -> authorized_keys del servidor admin
resource "kubernetes_secret_v1" "ssh_admin_autorizadas" {
  metadata {
    name      = "ssh-admin-authorized-keys"
    namespace = var.namespace
  }
  type = "Opaque"
  data = {
    "authorized_keys" = file("${path.module}/${var.ssh_host_public_key}")
  }
}
