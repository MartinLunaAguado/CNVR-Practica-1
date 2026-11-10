#!/bin/bash
# =============================================================================
# config.sh -> parámetros comunes a todos los scripts (GRUPO 9).
# Deben coincidir con shared/terraform.tfvars. Los marcados con <-- hay que
# confirmarlos en el laboratorio (guía, Paso 3).
# =============================================================================

# Carpeta raíz del proyecto, calculada automáticamente
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Escenario de Kubernetes del laboratorio
K8S_DIR=/mnt/tmp/k8s_lab-calico-v02
SHARED="$K8S_DIR/shared"

GRUPO=9

# Nodos (nombres que resuelve el host; si no resuelven, poned las IP)
WORKERS="k8s-worker1 k8s-worker2"
NODO_TERRAFORM=terraform
WORKER1_IP=10.10.10.11   # k8s_LAN (Figura 2 de la P1.4)
WORKER2_IP=10.10.10.12
HOST_IP=10.10.20.2       # IP del host en user_LAN

# Imágenes y usuarios (enunciado, apartado 2, paso 1)
IMAGEN_WEB=dgsgiros/nginx-ssh:latest
IMAGEN_ADMIN=dgsgiros/admin-ssh:latest
USUARIO_WEB=webuser
USUARIO_ADMIN=adminuser
ADMIN_NODEPORT=30022

# VLAN
VLAN_PARENT_IF=eth2      # <-- interfaz de los workers conectada a VlanNet
VLAN_ID=100              # <-- la misma que en vnx/cnvr-lxc-vlan.xml

# IPs en la VLAN
ADMIN_VLAN_IP=10.1.100.10
BBDD_IP=10.1.100.21
LOGS_IP=10.1.100.22

# Claves SSH
#   Par I  (admin -> web y LXC):  admin_web_rsa / admin_web_rsa.pub
#   Par II (host  -> admin):      host_admin_rsa / host_admin_rsa.pub
KEYS_DIR="$REPO/shared/keys"
CLAVE_HOST="$KEYS_DIR/host_admin_rsa"

# Si el Ingress Controller se publica de forma especial, fijad aquí la URL base
# (p.ej. INGRESS_URL=http://10.10.10.11:31234). Vacío = se detecta sola.
INGRESS_URL=""

# Copia el proyecto Terraform a la carpeta compartida con la máquina terraform.
# No toca el estado de Terraform (.terraform, terraform.tfstate) que haya allí.
sync_shared() {
  mkdir -p "$SHARED/scripts"
  cp -r "$REPO/shared/." "$SHARED/"
  cp "$REPO/scripts/05-terraform-deploy.sh" "$SHARED/scripts/"
  echo "[+] Proyecto copiado a $SHARED"
}
