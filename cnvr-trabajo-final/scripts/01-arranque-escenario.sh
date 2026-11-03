#!/bin/bash
# =============================================================================
# 01-arranque-escenario.sh  (ejecutar en el HOST del laboratorio)
# -----------------------------------------------------------------------------
# Arranca el escenario de Kubernetes con Calico + nodo terraform (P1.4, ap. 3)
# y copia los ficheros Terraform a la carpeta compartida /shared.
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
mkdir -p "$SHARED"
cp -r "$REPO/shared/." "$SHARED/"
mkdir -p "$SHARED/scripts" && cp "$REPO/scripts/04-terraform-deploy.sh" "$SHARED/scripts/"

echo "== Hecho. Comprobad:  kubectl get nodes   (los 3 nodos en Ready)"
