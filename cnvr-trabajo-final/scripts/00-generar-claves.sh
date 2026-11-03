#!/bin/bash
# =============================================================================
# 00-generar-claves.sh  (ejecutar en el HOST, una sola vez)
# -----------------------------------------------------------------------------
# Genera los dos pares de claves SSH (sin contraseña):
#   shared/keys/admin_key(.pub) -> admin entra a web y LXC
#   shared/keys/host_key(.pub)  -> host entra al admin
# y copia la pública del admin al escenario VNX (authorized_keys de los LXC).
# =============================================================================
set -e
source "$(dirname "$0")/config.sh"

mkdir -p "$REPO/shared/keys"
cd "$REPO/shared/keys"

for k in admin_key host_key; do
  if [ -f "$k" ]; then
    echo "[=] $k ya existe, no se regenera"
  else
    ssh-keygen -t ed25519 -N "" -C "${k}@cnvr-g${GRUPO}" -f "$k"
    echo "[+] Generada $k"
  fi
done
chmod 600 admin_key host_key

cp admin_key.pub "$REPO/vnx/conf/ssh/authorized_keys"
echo "[+] admin_key.pub copiada a vnx/conf/ssh/authorized_keys"
