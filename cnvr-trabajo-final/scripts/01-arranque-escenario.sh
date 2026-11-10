#!/bin/bash
# =============================================================================
# 01-arranque-escenario.sh  (HOST)
# -----------------------------------------------------------------------------
# Arranca el escenario de Kubernetes con Calico y el nodo terraform (apartado 3
# de la práctica 1.4) y copia el proyecto a la carpeta compartida /shared.
# =============================================================================
set -e
source "$(dirname "$0")/config.sh"

echo "== 1. Descargando y arrancando el escenario Kubernetes (Calico)"
/lab/cnvr/bin/get-k8s-calico
cd "$K8S_DIR"
./bin/start-k8s-calico

echo "== 2. Arrancando el nodo terraform"
sudo vnx -f k8s_lab-terraform.xml --create
sudo vnx -f k8s_lab-terraform.xml -x install-terraform

echo "== 3. Credenciales del clúster para el host y para el nodo terraform"
./bin/get-master-kubeconf
./bin/set-terraform-kubeconf

echo "== 4. Copiando el proyecto Terraform a $SHARED"
sync_shared

echo "== Hecho. Comprobad:"
echo "   kubectl get nodes                      (3 nodos en Ready)"
echo "   kubectl get pods -n ingress-nginx      (controlador en Running)"
echo "   ssh root@$NODO_TERRAFORM terraform --version"
