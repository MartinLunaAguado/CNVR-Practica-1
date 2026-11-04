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
# Terraform carga TODOS los .tf de /shared: si quedan los de la P1.4 (que tiene
# también un "default_deny_all") o su terraform.tfstate, habría conflictos.
AJENOS=$(cd "$SHARED" && ls *.tf 2>/dev/null | while read -r f; do
           [ -f "$REPO/shared/$f" ] || echo "$f"; done)
if grep -qE '"name": "(web_servers|tester|tester_egress|nginx_ingress)"' "$SHARED/terraform.tfstate" 2>/dev/null; then
  AJENOS="$AJENOS terraform.tfstate (con recursos de la P1.4)"
fi
if [ -n "$AJENOS" ]; then
  echo "!! En $SHARED hay ficheros que no son de este proyecto (¿restos de la P1.4?):"
  echo "$AJENOS" | sed 's/^/     /'
  echo "!! Movedlos a otra carpeta (y haced antes 'terraform destroy' si siguen desplegados) y relanzad."
  exit 1
fi
cp -r "$REPO/shared/." "$SHARED/"
mkdir -p "$SHARED/scripts" && cp "$REPO/scripts/04-terraform-deploy.sh" "$SHARED/scripts/"

echo "== Hecho. Comprobad:  kubectl get nodes   (los 3 nodos en Ready)"
