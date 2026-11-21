#!/bin/bash
# =============================================================================
# 01-arranque-escenario.sh  (HOST)
# -----------------------------------------------------------------------------
# Arranca el escenario de Kubernetes con Calico y el nodo terraform (apartado 3
# de la práctica 1.4) y copia el proyecto a la carpeta compartida /shared.
# =============================================================================
set -e
source "$(dirname "$0")/config.sh"

echo "== 1. Descargando y arrancando el escenario Kubernetes (Calico)"
/lab/cnvr/bin/get-k8s-calico
cd "$K8S_DIR"
./bin/start-k8s-calico

echo "== 2. Arrancando el nodo terraform"
sudo vnx -f k8s_lab-terraform.xml --create
sudo vnx -f k8s_lab-terraform.xml -x install-terraform

echo "== 3. Credenciales del clúster para el host y para el nodo terraform"
./bin/get-master-kubeconf
./bin/set-terraform-kubeconf

echo "== 4. MetalLB (aviso del profesor, 20/11): el Service del Ingress Controller"
echo "      es LoadBalancer y necesita MetalLB para tener EXTERNAL-IP"
metallb_ok(){
  kubectl get ipaddresspools.metallb.io -n metallb-system --no-headers 2>/dev/null | grep -q default-pool &&
  kubectl get l2advertisements.metallb.io -n metallb-system --no-headers 2>/dev/null | grep -q default-l2-advertisement
}
for intento in 1 2 3; do
  metallb_ok && break
  echo "   MetalLB sin configurar (intento $intento/3): config_metallb"
  sleep 20   # deja arrancar los Pods de MetalLB antes de aplicar su configuración
  sudo vnx -f k8s_lab-calico.xml -x config_metallb || true
done
kubectl get ipaddresspools.metallb.io -n metallb-system || true
kubectl get l2advertisements.metallb.io -n metallb-system || true
metallb_ok || echo "!! MetalLB sigue sin configurar: repetid  sudo vnx -f k8s_lab-calico.xml -x config_metallb  en $K8S_DIR"

echo "== 5. Copiando el proyecto Terraform a $SHARED"
sync_shared

echo "== Hecho. Comprobad:"
echo "   kubectl get nodes                      (3 nodos en Ready)"
echo "   kubectl get svc -n ingress-nginx       (ingress-nginx-controller con EXTERNAL-IP 10.10.10.2x)"
echo "   ssh root@$NODO_TERRAFORM terraform --version"
echo "   (si 'terraform: command not found': sudo vnx -f k8s_lab-terraform.xml -x install-terraform"
echo "    en $K8S_DIR; si vuelve a fallar, avisad a los profesores por correo)"
