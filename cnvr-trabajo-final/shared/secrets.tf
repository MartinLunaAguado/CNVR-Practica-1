# =============================================================================
# secrets.tf  (Apartado 2, paso 5 del enunciado)
# -----------------------------------------------------------------------------
# Las claves SSH se reparten a los Pods con recursos Secret creados desde
# Terraform (equivalente a "kubectl create secret generic ... --from-file").
#
# Dos pares de claves independientes, generados en el host con
# scripts/00-generar-claves.sh:
#
#   Par I  (administración -> servidores web)
#       privada  -> Pod admin                   (Secret ssh-admin-private-key)
#       pública  -> authorized_keys de los web  (Secret ssh-web-authorized-keys)
#                   y de los contenedores LXC   (la copia VNX con filetree)
#
#   Par II (exterior -> administración)
#       privada  -> se queda en el host, NO se sube al clúster
#       pública  -> authorized_keys del admin   (Secret ssh-admin-authorized-keys)
#
# El admin usa un Secret distinto para cada clave, como recomienda el enunciado,
# y los tres servidores web comparten un único Secret.
#
# En "data" se escribe el contenido en claro: el proveedor lo codifica en
# base64. OJO: el contenido también queda en terraform.tfstate, así que ese
# fichero es tan sensible como la propia clave (está en .gitignore).
# =============================================================================

# Par I, clave PRIVADA -> la usa el admin para entrar en los servidores web
resource "kubernetes_secret_v1" "ssh_admin_privada" {
  metadata {
    name      = "ssh-admin-private-key"
    namespace = var.namespace
  }
  type = "Opaque"
  data = {
    "id_rsa" = file("${path.module}/${var.clave_admin_web_privada}")
  }
}

# Par II, clave PÚBLICA -> autorizada en el admin (acceso desde el host)
resource "kubernetes_secret_v1" "ssh_admin_autorizadas" {
  metadata {
    name      = "ssh-admin-authorized-keys"
    namespace = var.namespace
  }
  type = "Opaque"
  data = {
    "authorized_keys" = file("${path.module}/${var.clave_host_admin_publica}")
  }
}

# Par I, clave PÚBLICA -> autorizada en TODOS los servidores web
resource "kubernetes_secret_v1" "ssh_web_autorizadas" {
  metadata {
    name      = "ssh-web-authorized-keys"
    namespace = var.namespace
  }
  type = "Opaque"
  data = {
    "authorized_keys" = file("${path.module}/${var.clave_admin_web_publica}")
  }
}
