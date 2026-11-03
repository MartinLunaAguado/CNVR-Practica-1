#!/bin/bash
# =============================================================================
# 99-borrar.sh  (ejecutar en el HOST)
# -----------------------------------------------------------------------------
# 1) Destruye lo creado por Terraform (desde la máquina terraform).
# 2) Destruye el escenario LXC.
# 3) (Opcional) guarda una copia de /shared antes de que se pierda /mnt/tmp.
# =============================================================================
source "$(dirname "$0")/config.sh"

echo "== Copia de seguridad de $SHARED en ~/cnvr-backup-$(date +%F-%H%M)"
cp -r "$SHARED" ~/cnvr-backup-$(date +%F-%H%M) 2>/dev/null || true

echo "== terraform destroy (en la máquina terraform)"
ssh root@terraform "cd /shared && terraform destroy -auto-approve"

echo "== Destruyendo escenario LXC"
cd "$REPO/vnx" && sudo vnx -f cnvr-lxc-vlan.xml --destroy

echo "== Quitando subinterfaces VLAN de los workers"
for w in $WORKERS; do
  ssh root@"$w" "ip link del ${VLAN_PARENT_IF}.${VLAN_ID} 2>/dev/null || true"
done
