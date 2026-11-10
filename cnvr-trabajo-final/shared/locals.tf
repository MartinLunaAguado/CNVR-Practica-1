# =============================================================================
# locals.tf
# -----------------------------------------------------------------------------
# Valores calculados que se reutilizan en varios ficheros. Definir aquí las
# etiquetas evita escribirlas a mano (y desincronizarlas) en el Deployment,
# los Services y las NetworkPolicy (práctica 1.4, apartado 3.2).
# =============================================================================

locals {
  web_labels   = { app = "web" }
  admin_labels = { app = "admin" }

  # Ruta del Ingress: /servers-G9
  ruta_ingress = "/servers-G${var.grupo}"

  # Subinterfaz VLAN creada en los workers (p.ej. eth2.100)
  vlan_if = "${var.vlan_parent_if}.${var.vlan_id}"

  # Directorios .ssh de los usuarios de las imágenes
  ssh_dir_web   = "/home/${var.usuario_web}/.ssh"
  ssh_dir_admin = "/home/${var.usuario_admin}/.ssh"
}
