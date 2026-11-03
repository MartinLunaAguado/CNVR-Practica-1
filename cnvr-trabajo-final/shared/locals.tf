# =============================================================================
# locals.tf
# -----------------------------------------------------------------------------
# Valores calculados que se reutilizan en varios ficheros. Definir aquí las
# etiquetas evita tener que escribirlas a mano (y desincronizarlas) en el
# Deployment, en los Services y en las NetworkPolicy (P1.4, apartado 3.2).
# =============================================================================

locals {
  web_labels   = { app = "web" }
  admin_labels = { app = "admin" }

  # Ruta del Ingress: /servers-GX
  ruta_ingress = "/servers-G${var.grupo}"

  # Subinterfaz VLAN creada en los workers (p.ej. eth2.100)
  vlan_if = "${var.vlan_parent_if}.${var.vlan_id}"

  # Máscara de la VLAN (p.ej. "24") para la IPAM
  vlan_prefix = split("/", var.vlan_cidr)[1]
}
