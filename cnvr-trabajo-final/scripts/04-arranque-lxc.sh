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

corriendo(){ sudo lxc-info -n "$1" -s 2>/dev/null | grep -q RUNNING; }
if corriendo bbdd && corriendo logs; then
  echo "Los LXC bbdd y logs ya están arrancados: solo se repite la configuración"
else
  sudo vnx -f cnvr-lxc-vlan.xml --create
  echo "Esperando a que arranquen los contenedores y tengan red..."
  sleep 20
fi
# La secuencia se puede repetir: los exec esperan a tener DNS, solo quitan
# MySQL si está instalado e init.sql usa IF NOT EXISTS.
sudo vnx -f cnvr-lxc-vlan.xml -x configurar

echo "== Comprobación rápida"
for c in bbdd logs; do
  echo "--- $c"
  sudo lxc-attach -n $c -- ip -4 -br addr
  sudo lxc-attach -n $c -- ss -ltnu | grep -E ':(22|3306|514)[[:space:]]' || true
done
echo "bbdd debe escuchar en 22 y en 0.0.0.0:3306; logs en 22 y 514 (UDP y TCP)."
