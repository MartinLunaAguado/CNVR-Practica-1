#!/bin/bash
# =============================================================================
# config.sh -> parámetros comunes a todos los scripts. ¡Revisadlos!
# (Deben coincidir con shared/terraform.tfvars)
# =============================================================================

# Carpeta raíz del proyecto (la de este repositorio), calculada automáticamente
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Escenario de Kubernetes del laboratorio
K8S_DIR=/mnt/tmp/k8s_lab-calico-v02
SHARED="$K8S_DIR/shared"

GRUPO=99                 # número de grupo (igual que en terraform.tfvars)
WORKERS="k8s-worker1 k8s-worker2"
WORKER1_IP=10.10.10.11   # k8s_LAN (Figura 2 P1.4)
ADMIN_NODEPORT=30022

# VLAN
VLAN_PARENT_IF=eth2      # interfaz de los workers conectada a VlanNet (comprobar con 'ip a')
VLAN_ID=100

# IPs en la VLAN
ADMIN_VLAN_IP=10.1.100.10
BBDD_IP=10.1.100.21
LOGS_IP=10.1.100.22
