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

# IPs de los nodos en k8s_LAN (Figura 2 de la P1.4). Se usan IPs y no nombres
# porque el host no tiene por qué resolver "k8s-worker1", "terraform"...
# (si "ssh root@IP" pide contraseña, en los escenarios VNX suele ser "xxxx")
MASTER_IP=10.10.10.10
WORKER1_IP=10.10.10.11
WORKER2_IP=10.10.10.12
TERRAFORM_IP=10.10.10.13
WORKERS="$WORKER1_IP $WORKER2_IP"

ADMIN_NODEPORT=30022

# VLAN
VLAN_PARENT_IF=eth2      # interfaz de los workers conectada a VlanNet (comprobar con 'ip a')
VLAN_ID=100

# IPs en la VLAN
ADMIN_VLAN_IP=10.1.100.10
BBDD_IP=10.1.100.21
LOGS_IP=10.1.100.22
