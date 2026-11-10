#!/bin/bash
# =============================================================================
# 04-arranque-lxc.sh  (HOST)  -> Apartado 2, paso 6
# -----------------------------------------------------------------------------
# Arranca el escenario VNX con los contenedores LXC (bbdd y logs) y ejecuta la
# secuencia "configurar": filetree copia los ficheros de vnx/conf y exec
# instala y configura MariaDB, rsyslog y SSH.
# =============================================================================
set -e
source "$(dirname "$0")/config.sh"
cd "$REPO/vnx"

if [ ! -f conf/ssh/authorized_keys ]; then
  echo "Falta vnx/conf/ssh/authorized_keys: ejecutad antes 00-generar-claves.sh"
  exit 1
fi

sudo vnx -f cnvr-lxc-vlan.xml --create
echo "Esperando a que arranquen los contenedores y tengan red..."
sleep 20
sudo vnx -f cnvr-lxc-vlan.xml -x configurar

echo "== Comprobación rápida"
for c in bbdd logs; do
  echo "--- $c"
  sudo lxc-attach -n $c -- ip -4 -br addr
  sudo lxc-attach -n $c -- ss -ltnu | grep -E ':(22|3306|514)[[:space:]]' || true
done
echo "bbdd debe escuchar en 22 y 3306; logs en 22 y 514."
