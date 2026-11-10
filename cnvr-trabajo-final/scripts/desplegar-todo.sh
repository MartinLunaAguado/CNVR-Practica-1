#!/bin/bash
# =============================================================================
# desplegar-todo.sh  (HOST)  -> despliegue automático completo
# -----------------------------------------------------------------------------
# Ejecuta todos los pasos en orden. Usadlo cuando ya hayáis confirmado los
# valores de config.sh y terraform.tfvars (guía, Paso 3).
#   ./scripts/desplegar-todo.sh            -> todo, incluido arrancar Kubernetes
#   ./scripts/desplegar-todo.sh --sin-k8s  -> si el escenario ya está arrancado
# =============================================================================
set -e
D="$(dirname "$0")"
source "$D/config.sh"

"$D/00-generar-claves.sh"
if [ "$1" != "--sin-k8s" ]; then
  "$D/01-arranque-escenario.sh"
else
  sync_shared
fi
"$D/03-vlan-workers.sh"
"$D/04-arranque-lxc.sh"
ssh root@$NODO_TERRAFORM 'bash /shared/scripts/05-terraform-deploy.sh'
echo
echo "Despliegue terminado. Lanzad ahora: $D/06-pruebas.sh"
