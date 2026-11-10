#!/bin/bash
# =============================================================================
# 99-borrar.sh  (HOST)
# -----------------------------------------------------------------------------
# 1) Guarda una copia de /shared (ficheros .tf y estado) en la carpeta personal,
#    porque /mnt/tmp es volátil.
# 2) Destruye lo creado por Terraform (desde la máquina terraform).
# 3) Destruye el escenario LXC y quita las subinterfaces VLAN de los workers.
# No destruye el escenario de Kubernetes.
# =============================================================================
source "$(dirname "$0")/config.sh"

COPIA=~/cnvr-backup-$(date +%F-%H%M)
echo "== Copia de seguridad de $SHARED en $COPIA"
mkdir -p "$COPIA" && cp -r "$SHARED/." "$COPIA/" 2>/dev/null && rm -rf "$COPIA/.terraform"

echo "== terraform destroy (en la máquina terraform)"
ssh root@$NODO_TERRAFORM "cd /shared && terraform destroy -auto-approve -input=false"

echo "== Destruyendo el escenario LXC"
cd "$REPO/vnx" && sudo vnx -f cnvr-lxc-vlan.xml --destroy

echo "== Quitando las subinterfaces VLAN de los workers"
for w in $WORKERS; do
  ssh root@"$w" "ip link del ${VLAN_PARENT_IF}.${VLAN_ID} 2>/dev/null || true"
done
echo "Hecho."
