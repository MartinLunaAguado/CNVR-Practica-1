#!/bin/bash
# =============================================================================
# 07-cliente-bd.sh  (HOST)  -> OPCIONAL, para la prueba completa de la BD
# -----------------------------------------------------------------------------
# El enunciado pide comprobar que el admin y los servidores web pueden
# administrar la base de datos. Si las imágenes no traen cliente SQL, este
# script lo instala con apt (el enunciado indica que se puede usar sudo apt).
#
# Como default-deny-all bloquea la salida de los Pods, hace esto:
#   1. Crea con Terraform la política temporal "temporal-allow-egress".
#   2. Instala mariadb-client en el Pod admin y en los Pods web.
#   3. Elimina la política temporal con Terraform (vuelve el bloqueo total).
#
# OJO: lo instalado se pierde si el Pod se recrea (los Pods son efímeros).
# =============================================================================
source "$(dirname "$0")/config.sh"

tf(){ ssh root@$NODO_TERRAFORM "cd /shared && terraform apply -auto-approve -input=false $*"; }
instalar(){  # instalar <pod> <contenedor>
  kubectl exec "$1" -c "$2" -- sh -c '
    command -v mysql >/dev/null || command -v mariadb >/dev/null && { echo "ya instalado"; exit 0; }
    SUDO=""; [ "$(id -u)" != 0 ] && SUDO="sudo"
    export DEBIAN_FRONTEND=noninteractive
    $SUDO apt-get update -qq && $SUDO apt-get install -y -qq mariadb-client >/dev/null && echo "instalado"
  '
}

echo "== 1. Permitiendo temporalmente la salida de los Pods (Terraform)"
tf -var=permitir_salida_temporal=true | tail -3

echo "== 2. Instalando mariadb-client"
echo "--- admin";  instalar admin admin
for p in $(kubectl get pods -l app=web -o jsonpath='{.items[*].metadata.name}'); do
  echo "--- $p"; instalar "$p" web
done

echo "== 3. Eliminando la política temporal (Terraform)"
tf | tail -3
kubectl get networkpolicy
echo "Hecho. Volved a lanzar ./scripts/06-pruebas.sh para la prueba P9 completa."
