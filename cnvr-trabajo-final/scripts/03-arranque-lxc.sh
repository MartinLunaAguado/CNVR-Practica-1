#!/bin/bash
# =============================================================================
# 03-arranque-lxc.sh  (ejecutar en el HOST)  -> Apartado 2, punto 6
# -----------------------------------------------------------------------------
# Arranca el escenario VNX con los contenedores LXC (bbdd y logs) y ejecuta
# la secuencia "configurar" (instala MariaDB/rsyslog/SSH y copia ficheros).
# =============================================================================
set -e
source "$(dirname "$0")/config.sh"
cd "$REPO/vnx"

[ -f conf/ssh/authorized_keys ] || { echo "Falta conf/ssh/authorized_keys: ejecuta 00-generar-claves.sh"; exit 1; }

sudo vnx -f cnvr-lxc-vlan.xml --create
echo "Esperando a que arranquen los contenedores..."; sleep 15
sudo vnx -f cnvr-lxc-vlan.xml -x configurar

echo "== Comprobación rápida"
sudo lxc-attach -n bbdd -- systemctl is-active mariadb ssh || true
sudo lxc-attach -n logs -- systemctl is-active rsyslog ssh || true
