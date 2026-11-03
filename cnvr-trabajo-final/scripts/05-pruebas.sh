#!/bin/bash
# =============================================================================
# 05-pruebas.sh  (ejecutar en el HOST)  -> verificación (Apartado 2.7, 3, 4, 5)
# -----------------------------------------------------------------------------
# Hace las comprobaciones automáticas y muestra los resultados. Haced capturas
# de pantalla de cada bloque para la memoria.
# =============================================================================
source "$(dirname "$0")/config.sh"
KEY="$REPO/shared/keys/host_key"
SSH_ADMIN="ssh -i $KEY -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -p $ADMIN_NODEPORT root@$WORKER1_IP"
sep(){ echo; echo "==================== $* ===================="; }

sep "P1. Recursos desplegados"
kubectl get deploy,pods,svc,ingress,networkpolicy -o wide
kubectl get network-attachment-definitions

sep "P2. Interfaces extra (Multus) en los Pods"
for p in $(kubectl get pods -l app=web -o name); do
  echo "--- $p"; kubectl exec "$p" -c web -- ip -4 addr show net1
done
echo "--- pod/admin"; kubectl exec admin -c admin -- ip -4 addr show net1

sep "P3. Página personalizada vía Ingress (/servers-G$GRUPO)"
NP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller \
      -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}' 2>/dev/null)
EXT=$(kubectl -n ingress-nginx get svc ingress-nginx-controller \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
if [ -n "$EXT" ]; then URL="http://$EXT/servers-G$GRUPO"; else URL="http://$WORKER1_IP:$NP/servers-G$GRUPO"; fi
echo "URL: $URL"
for i in $(seq 1 9); do curl -s "$URL" | grep -o 'web-[a-z0-9]*-[a-z0-9]*' | head -1; done | sort | uniq -c
echo "(Deben aparecer los 3 Pods distintos)"

sep "P4. SSH host -> admin (debe FUNCIONAR)"
$SSH_ADMIN hostname

sep "P5. SSH al admin desde OTRO origen (debe FALLAR: NetworkPolicy ipBlock)"
echo "Desde k8s-master (10.10.10.10):"
ssh root@k8s-master "timeout 5 bash -c '</dev/tcp/$WORKER1_IP/$ADMIN_NODEPORT' && echo ABIERTO || echo BLOQUEADO"

sep "P6. Acceso directo a Pods web desde fuera del Ingress (debe FALLAR)"
WEBIP=$(kubectl get pods -l app=web -o jsonpath='{.items[0].status.podIP}')
SVCIP=$(kubectl get svc web-svc -o jsonpath='{.spec.clusterIP}')
echo "Desde k8s-master a la IP del Pod ($WEBIP:80) y al Service ($SVCIP:8080):"
ssh root@k8s-master "curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://$WEBIP || echo BLOQUEADO"
ssh root@k8s-master "curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://$SVCIP:8080 || echo BLOQUEADO"

sep "P7. Desde admin: ping y SSH por la VLAN a web, bbdd y logs"
WEB_VLAN_IPS=$(kubectl get pods -l app=web -o json | python3 -c '
import json,sys
for p in json.load(sys.stdin)["items"]:
    st=json.loads(p["metadata"]["annotations"].get("k8s.v1.cni.cncf.io/network-status","[]"))
    for n in st:
        if n.get("interface")=="net1": print(n["ips"][0])')
for ip in $WEB_VLAN_IPS $BBDD_IP $LOGS_IP; do
  echo "--- $ip"
  $SSH_ADMIN "ping -c 2 -W 2 $ip >/dev/null && echo ping OK || echo ping FALLA; ssh -o ConnectTimeout=5 root@$ip hostname"
done

sep "P8. Base de datos desde admin y desde un servidor web"
$SSH_ADMIN "mysql -h $BBDD_IP -u cnvr -pcnvr2627 cnvr -e 'INSERT INTO accesos(origen,mensaje) VALUES (\"admin\",\"prueba\"); SELECT * FROM accesos;' \
            || (nc -zv $BBDD_IP 3306)"
W1=$(echo $WEB_VLAN_IPS | cut -d' ' -f1)
$SSH_ADMIN "ssh root@$W1 \"mysql -h $BBDD_IP -u cnvr -pcnvr2627 cnvr -e 'SELECT COUNT(*) FROM accesos;' || nc -zv $BBDD_IP 3306\""

sep "P9. Envío de un log al servidor de logs"
$SSH_ADMIN "logger -n $LOGS_IP -P 514 -d 'Prueba CNVR desde admin' && echo enviado"
sudo lxc-attach -n logs -- sh -c 'tail -n 3 /var/log/remoto/*.log'
