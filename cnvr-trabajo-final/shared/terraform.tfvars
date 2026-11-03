# =============================================================================
# terraform.tfvars  -> valores concretos de las variables (se carga solo)
# ¡¡REVISAR LOS MARCADOS CON  <-- !!
# =============================================================================

grupo = 99 # <-- poned vuestro número de grupo

# Imágenes que proporciona el profesorado (ya incluyen el servidor SSH)
imagen_web   = "CAMBIAR/imagen-web:tag"   # <-- nombre exacto de la imagen web
imagen_admin = "CAMBIAR/imagen-admin:tag" # <-- nombre exacto de la imagen admin
web_root     = "/usr/share/nginx/html"    # <-- comprobar en la imagen web

# Red del escenario (Figura 2 de la práctica 1.4)
host_ip         = "10.10.20.2"
admin_node      = "k8s-worker1"
admin_node_port = 30022

# VLAN compartida con VNX
vlan_parent_if = "eth2" # <-- interfaz de los workers conectada a VlanNet
vlan_id        = 100
vlan_cidr      = "10.1.100.0/24"
vlan_admin_ip  = "10.1.100.10/24"
