#!/bin/bash
# =============================================================================
# 02-inspeccionar-imagenes.sh  (HOST)  -> Paso 3 de la guía
# -----------------------------------------------------------------------------
# Arranca un Pod temporal con cada imagen proporcionada (en un namespace
# aparte) y muestra lo que el proyecto da por supuesto, para confirmarlo:
#   usuario y grupo, directorio home y .ssh, configuración de sshd, puertos a
#   la escucha, directorio raíz de Nginx y herramientas disponibles.
# También muestra los datos del clúster que hay que copiar a terraform.tfvars.
# No modifica nada del despliegue.
# =============================================================================
source "$(dirname "$0")/config.sh"
NS=inspeccion
sep(){ echo; echo "==================== $* ===================="; }

kubectl create namespace $NS >/dev/null 2>&1

inspeccionar() {   # inspeccionar <nombre-pod> <imagen> <usuario>
  local pod=$1 img=$2 usr=$3
  sep "Imagen $img (usuario esperado: $usr)"
  kubectl -n $NS run "$pod" --image="$img" --restart=Never >/dev/null
  if ! kubectl -n $NS wait --for=condition=Ready "pod/$pod" --timeout=180s >/dev/null; then
    echo "!! El Pod no arranca. Mirad: kubectl -n $NS describe pod $pod"
    return
  fi
  kubectl -n $NS exec "$pod" -- sh -c "
    echo '--- Usuario con el que arranca el contenedor:'; id
    echo '--- Usuario $usr (debe tener gid=1000):'; id $usr; getent passwd $usr
    echo '--- Home y .ssh (permisos y dueño):'; ls -ld /home/$usr /home/$usr/.ssh 2>&1
    echo '--- sudo sin contraseña para $usr:'
    su $usr -c 'sudo -n true' 2>/dev/null && echo SI || echo 'NO (o no se pudo comprobar)'
    echo '--- sshd_config (líneas activas):'
    grep -Ev '^[[:space:]]*(#|\$)' /etc/ssh/sshd_config 2>/dev/null
    echo '--- Puertos a la escucha (deben estar el 22 y, en web, el 80):'
    (ss -ltn 2>/dev/null || netstat -ltn 2>/dev/null) | grep -E ':(22|80)[[:space:]]'
    echo '--- Nginx: directorio raíz (-> variable web_root):'
    nginx -T 2>/dev/null | grep -E '^[[:space:]]*root ' | sort -u
    echo '--- Herramientas:'
    for t in ping nmap curl ip nc logger mysql mariadb; do
      printf '  %-8s %s\n' \$t \"\$(command -v \$t || echo NO)\"
    done
  "
  kubectl -n $NS delete pod "$pod" --wait=false >/dev/null
}

inspeccionar insp-web   "$IMAGEN_WEB"   "$USUARIO_WEB"
inspeccionar insp-admin "$IMAGEN_ADMIN" "$USUARIO_ADMIN"

sep "Datos del clúster para terraform.tfvars y config.sh"
echo "--- Interfaces de k8s-worker1 (¿cuál está en VlanNet? -> vlan_parent_if):"
ssh root@k8s-worker1 ip -br addr
echo
echo "--- Multus y Whereabouts:"
kubectl get pods -A | grep -Ei 'multus|whereabouts' || echo "  (no aparecen)"
kubectl get crd | grep -E 'network-attachment-definitions|whereabouts' || true
echo
echo "--- Ingress Controller: etiquetas (-> ingress_controller_labels), IP y red:"
kubectl -n ingress-nginx get pods --show-labels -o wide
echo
echo "--- Ingress Controller: cómo se publica (NodePort / LoadBalancer):"
kubectl -n ingress-nginx get svc
kubectl get ingressclass
echo
echo "--- Nodos (etiqueta kubernetes.io/hostname para el nodeSelector):"
kubectl get nodes -o wide -L kubernetes.io/hostname

kubectl delete namespace $NS --wait=false >/dev/null
