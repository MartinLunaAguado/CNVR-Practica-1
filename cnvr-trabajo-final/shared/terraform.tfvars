# =============================================================================
# terraform.tfvars -> valores del GRUPO 9 (Terraform lo carga automáticamente)
# Martín Luna Aguado y Brayan Guarachi Apaza
#
# Los marcados con <-- hay que confirmarlos en el laboratorio (guía, Paso 3).
# =============================================================================

grupo = 9

# Imágenes y usuarios que indica el enunciado (versión del 5 de noviembre)
imagen_web    = "dgsgiros/nginx-ssh:latest"
usuario_web   = "webuser"
imagen_admin  = "dgsgiros/admin-ssh:latest"
usuario_admin = "adminuser"
ssh_gid       = 1000

web_root = "/usr/share/nginx/html" # <-- lo muestra 02-inspeccionar-imagenes.sh

# Red del escenario (Figura 2 de la práctica 1.4)
host_ip         = "10.10.20.2"
admin_node      = "k8s-worker1"
admin_node_ip   = "10.10.10.11"
admin_node_port = 30022

# VLAN compartida con VNX
vlan_parent_if = "eth2" # <-- interfaz de los workers conectada a VlanNet
vlan_id        = 100    # <-- la misma que en el XML de VNX
vlan_cidr      = "10.1.100.0/24"
vlan_admin_ip  = "10.1.100.10/24"
bbdd_ip        = "10.1.100.21"
logs_ip        = "10.1.100.22"

# Etiquetas del Ingress Controller  <-- kubectl get pods -n ingress-nginx --show-labels
ingress_controller_labels = {
  "app.kubernetes.io/name"      = "ingress-nginx"
  "app.kubernetes.io/component" = "controller"
}
