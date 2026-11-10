#!/bin/bash
# =============================================================================
# 00-generar-claves.sh  (HOST, una sola vez)  -> Apartado 2, paso 5
# -----------------------------------------------------------------------------
# Genera en el host los DOS pares de claves SSH independientes que pide el
# enunciado (RSA 4096, sin frase de paso):
#
#   Par I  (administración -> servidores web):  shared/keys/admin_web_rsa(.pub)
#       privada -> Pod admin (Secret)    pública -> web (Secret) y LXC (filetree)
#   Par II (exterior -> administración):        shared/keys/host_admin_rsa(.pub)
#       privada -> se queda en el host   pública -> Pod admin (Secret)
#
# Y copia la pública del Par I al escenario VNX (authorized_keys de los LXC).
# =============================================================================
set -e
source "$(dirname "$0")/config.sh"

mkdir -p "$KEYS_DIR"
cd "$KEYS_DIR"

for k in admin_web_rsa host_admin_rsa; do
  if [ -f "$k" ]; then
    echo "[=] $k ya existe, no se regenera"
  else
    ssh-keygen -q -t rsa -b 4096 -N "" -C "${k}@cnvr-g${GRUPO}" -f "$k"
    echo "[+] Generado el par $k / $k.pub"
  fi
done
chmod 600 admin_web_rsa host_admin_rsa
chmod 644 admin_web_rsa.pub host_admin_rsa.pub

cp admin_web_rsa.pub "$REPO/vnx/conf/ssh/authorized_keys"
echo "[+] admin_web_rsa.pub copiada a vnx/conf/ssh/authorized_keys (para los LXC)"
ls -l "$KEYS_DIR"
