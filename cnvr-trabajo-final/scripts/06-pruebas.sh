#!/bin/bash
# =============================================================================
# 06-pruebas.sh  (HOST)  -> verificación de todos los requisitos
# -----------------------------------------------------------------------------
# Ejecuta las pruebas P1-P10 de la guía y marca cada comprobación con [OK] o
# [FALLO]. Incluye las pruebas NEGATIVAS (lo que debe estar bloqueado).
# Haced una captura de cada bloque para la memoria.
# =============================================================================
source "$(dirname "$0")/config.sh"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=6 -o BatchMode=yes"
ADMIN="ssh -i $CLAVE_HOST $SSH_OPTS -p $ADMIN_NODEPORT $USUARIO_ADMIN@$WORKER1_IP"
RUTA="/servers-G$GRUPO"
OKS=0; KOS=0
sep(){ echo; echo "==================== $* ===================="; }
ok(){ echo "  [OK]    $*"; OKS=$((OKS+1)); }
ko(){ echo "  [FALLO] $*"; KOS=$((KOS+1)); }
# debe_ir  "descripción" comando...  -> OK si el comando funciona
debe_ir(){ local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else ko "$d"; fi; }
# debe_fallar "descripción" comando... -> OK si el comando NO funciona (bloqueado)
debe_fallar(){ local d="$1"; shift; if "$@" >/dev/null 2>&1; then ko "$d -> debía estar BLOQUEADO"; else ok "$d (bloqueado)"; fi; }

WEB_PODS=$(kubectl get pods -l app=web -o jsonpath='{.items[*].metadata.name}')
WEB1=$(echo $WEB_PODS | cut -d' ' -f1)
WEB2=$(echo $WEB_PODS | cut -d' ' -f2)

# -----------------------------------------------------------------------------
sep "P1. Recursos desplegados"
kubectl get deploy,pods,svc,ingress,networkpolicy -o wide
kubectl get network-attachment-definitions
N=$(kubectl get pods -l app=web --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
[ "$N" -ge 3 ] && ok "$N Pods web en Running" || ko "Solo $N Pods web en Running"
NODO=$(kubectl get pod admin -o jsonpath='{.spec.nodeName}')
[ "$NODO" = "k8s-worker1" ] && ok "Pod admin en k8s-worker1 (nodeSelector)" || ko "Pod admin en '$NODO'"
ETP=$(kubectl get svc admin-svc -o jsonpath='{.spec.type}/{.spec.externalTrafficPolicy}')
[ "$ETP" = "NodePort/Local" ] && ok "admin-svc es NodePort con externalTrafficPolicy Local" || ko "admin-svc: $ETP"
TIPO=$(kubectl get svc web-svc -o jsonpath='{.spec.type} {.spec.ports[0].port}->{.spec.ports[0].targetPort}')
[ "$TIPO" = "ClusterIP 8080->80" ] && ok "web-svc es ClusterIP 8080->80" || ko "web-svc: $TIPO"

# -----------------------------------------------------------------------------
sep "P2. Interfaz adicional de Multus (net1) en la VLAN"
WEB_VLAN_IPS=""
for p in $WEB_PODS; do
  ip=$(kubectl exec "$p" -c web -- ip -4 -o addr show net1 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
  [ -n "$ip" ] && ok "$p tiene net1 = $ip" || ko "$p no tiene interfaz net1"
  WEB_VLAN_IPS="$WEB_VLAN_IPS $ip"
done
ip=$(kubectl exec admin -c admin -- ip -4 -o addr show net1 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
[ "$ip" = "$ADMIN_VLAN_IP" ] && ok "admin tiene net1 = $ip (IP fija)" || ko "admin net1 = '$ip' (esperada $ADMIN_VLAN_IP)"
W1_VLAN=$(echo $WEB_VLAN_IPS | cut -d' ' -f1)

# -----------------------------------------------------------------------------
sep "P3. Página personalizada y reparto de carga por el Ingress ($RUTA)"
if [ -z "$INGRESS_URL" ]; then
  EXT=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  NP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}' 2>/dev/null)
  if   [ -n "$EXT" ]; then INGRESS_URL="http://$EXT"
  elif [ -n "$NP"  ]; then INGRESS_URL="http://$WORKER1_IP:$NP"
  else                     INGRESS_URL="http://$WORKER1_IP"; fi
fi
URL="$INGRESS_URL$RUTA"
echo "URL: $URL"
COD=$(curl -s -m 6 -o /dev/null -w '%{http_code}' "$URL")
[ "$COD" = "200" ] && ok "El Ingress responde 200 en $RUTA" || ko "El Ingress responde '$COD' en $RUTA"
for i in $(seq 1 12); do curl -s -m 6 "$URL" | grep -o 'web-[a-z0-9]*-[a-z0-9]*' | head -1; done | sort | uniq -c
DIST=$(for i in $(seq 1 12); do curl -s -m 6 "$URL" | grep -o 'web-[a-z0-9]*-[a-z0-9]*' | head -1; done | sort -u | wc -l)
[ "$DIST" -ge 2 ] && ok "Responden $DIST Pods distintos (cada uno muestra su nombre)" || ko "Solo responde $DIST Pod"
COD=$(curl -s -m 6 -o /dev/null -w '%{http_code}' "$INGRESS_URL/otra-ruta")
[ "$COD" = "404" ] && ok "Otra ruta distinta devuelve 404 (solo se publica $RUTA)" || echo "  [info]  /otra-ruta devuelve $COD"

# -----------------------------------------------------------------------------
sep "P4. SSH host -> admin con clave (Par II), por worker1:$ADMIN_NODEPORT"
SALIDA=$($ADMIN 'echo "$(whoami) ${SSH_CLIENT%% *}"' 2>&1)
echo "  Sesión: $SALIDA   (usuario e IP origen que ve el Pod)"
echo "$SALIDA" | grep -q "^$USUARIO_ADMIN " && ok "Entra como $USUARIO_ADMIN sin contraseña" || ko "No se pudo entrar al admin: $SALIDA"
echo "$SALIDA" | grep -q " $HOST_IP\$" && ok "El Pod ve la IP real del host ($HOST_IP): se conserva la IP origen" \
                                       || ko "El Pod no ve $HOST_IP como origen"

# -----------------------------------------------------------------------------
sep "P5. SSH al admin desde orígenes NO autorizados (debe fallar)"
debe_fallar "Host -> worker2:$ADMIN_NODEPORT (con Local no hay Pod admin en ese nodo)" \
  timeout 6 bash -c "</dev/tcp/$WORKER2_IP/$ADMIN_NODEPORT"
echo "  Desde la máquina $NODO_TERRAFORM (otra IP origen); puede pedir su contraseña:"
R=$(ssh -o ConnectTimeout=6 root@$NODO_TERRAFORM "timeout 6 bash -c '</dev/tcp/$WORKER1_IP/$ADMIN_NODEPORT' 2>/dev/null && echo ABIERTO || echo BLOQUEADO" 2>/dev/null)
case "$R" in
  BLOQUEADO) ok "$NODO_TERRAFORM -> worker1:$ADMIN_NODEPORT (bloqueado por la NetworkPolicy ipBlock)";;
  ABIERTO)   ko "$NODO_TERRAFORM -> worker1:$ADMIN_NODEPORT está ABIERTO";;
  *)         echo "  [info]  No se pudo lanzar la prueba desde $NODO_TERRAFORM; hacedla a mano";;
esac

# -----------------------------------------------------------------------------
sep "P6. NetworkPolicy: accesos que deben estar bloqueados"
WEB_IP=$(kubectl get pod "$WEB1" -o jsonpath='{.status.podIP}')
WEB2_IP=$(kubectl get pod "$WEB2" -o jsonpath='{.status.podIP}')
SVC_IP=$(kubectl get svc web-svc -o jsonpath='{.spec.clusterIP}')
ADMIN_IP=$(kubectl get pod admin -o jsonpath='{.status.podIP}')
NS=pruebas-np
kubectl create namespace $NS >/dev/null 2>&1
kubectl -n $NS run tester --image=busybox:1.36 --restart=Never --command -- sleep 900 >/dev/null 2>&1
kubectl -n $NS wait --for=condition=Ready pod/tester --timeout=120s >/dev/null
T="kubectl -n $NS exec tester --"
echo "  Pod 'tester' en otro namespace (sin políticas propias):"
debe_ir     "tester -> Ingress Controller$RUTA (control: el tester sí tiene red)" \
  $T wget -T 6 -qO- "http://ingress-nginx-controller.ingress-nginx.svc.cluster.local$RUTA"
debe_fallar "tester -> Pod web $WEB_IP:80 directo" $T wget -T 6 -qO- "http://$WEB_IP"
debe_fallar "tester -> Service web-svc $SVC_IP:8080" $T wget -T 6 -qO- "http://$SVC_IP:8080"
BANNER=$($T sh -c "nc -w 6 $ADMIN_IP 22 </dev/null" 2>/dev/null)
echo "$BANNER" | grep -q SSH && ko "tester -> Pod admin $ADMIN_IP:22 está ABIERTO" || ok "tester -> Pod admin $ADMIN_IP:22 (bloqueado)"
kubectl delete namespace $NS --wait=false >/dev/null
echo "  Desde los propios Pods (deny-all de salida y de entrada):"
debe_fallar "$WEB1 -> $WEB2 ($WEB2_IP:80) por la red del clúster" \
  kubectl exec "$WEB1" -c web -- curl -s -m 6 -o /dev/null "http://$WEB2_IP"
debe_fallar "$WEB1 -> Internet (ping 8.8.8.8)" kubectl exec "$WEB1" -c web -- ping -c 1 -W 3 8.8.8.8

# -----------------------------------------------------------------------------
sep "P7. Conectividad por la VLAN desde el admin (ping)"
for ip in $WEB_VLAN_IPS $BBDD_IP $LOGS_IP; do
  debe_ir "admin -> $ip" $ADMIN "ping -c 2 -W 2 $ip || sudo -n ping -c 2 -W 2 $ip"
done
echo "  (Funciona con default-deny-all activo: net1 no pasa por Calico)"

# -----------------------------------------------------------------------------
sep "P8. SSH con clave (Par I) desde el admin a servidores web y LXC"
for ip in $WEB_VLAN_IPS; do
  R=$($ADMIN "ssh -o ConnectTimeout=6 -o BatchMode=yes $ip 'echo \$(whoami)@\$(hostname)'" 2>&1)
  echo "$R" | grep -q "^$USUARIO_WEB@web-" && ok "admin -> $ip : $R" || ko "admin -> $ip : $R"
done
for h in bbdd logs; do
  R=$($ADMIN "ssh -o ConnectTimeout=6 -o BatchMode=yes $h 'echo \$(whoami)@\$(hostname)'" 2>&1)
  echo "$R" | grep -q "^root@" && ok "admin -> $h : $R" || ko "admin -> $h : $R"
done

# -----------------------------------------------------------------------------
sep "P9. Base de datos: acceso desde el admin y desde un servidor web"
debe_ir "admin -> $BBDD_IP:3306 abierto (nmap)" \
  $ADMIN "nmap -Pn -p 3306 $BBDD_IP | grep -q '3306/tcp open'"
debe_ir "$WEB1 ($W1_VLAN) -> $BBDD_IP:3306 abierto (nmap)" \
  $ADMIN "ssh -o BatchMode=yes $W1_VLAN \"nmap -Pn -p 3306 $BBDD_IP | grep -q '3306/tcp open'\""
echo "  Administración de MariaDB desde el admin (por SSH al contenedor bbdd):"
$ADMIN "ssh -o BatchMode=yes bbdd \"mysql -t -e 'SHOW DATABASES; SELECT user,host FROM mysql.user; SELECT * FROM cnvr.accesos ORDER BY id DESC LIMIT 5;'\""
debe_ir "admin administra MariaDB (consulta por SSH)" \
  $ADMIN "ssh -o BatchMode=yes bbdd \"mysql -e 'SELECT COUNT(*) FROM cnvr.accesos'\""
# USER() devuelve usuario@IP_del_cliente: queda registrado desde qué máquina se conectó
SQL="INSERT INTO accesos(origen,mensaje) VALUES (USER(), CURRENT_USER()); SELECT * FROM accesos ORDER BY id DESC LIMIT 3;"
CLI='$(command -v mysql || command -v mariadb)'
if $ADMIN "[ -n \"$CLI\" ]" 2>/dev/null; then
  debe_ir "admin: cliente SQL contra $BBDD_IP (usuario cnvr)" \
    $ADMIN "$CLI -h $BBDD_IP -u cnvr -pcnvr2627 cnvr -e \"$SQL\""
  $ADMIN "$CLI -t -h $BBDD_IP -u cnvr -pcnvr2627 cnvr -e 'SELECT * FROM accesos ORDER BY id DESC LIMIT 5'"
else
  echo "  [info]  La imagen admin no trae cliente SQL. Para la prueba completa: ./scripts/07-cliente-bd.sh"
fi
if $ADMIN "ssh -o BatchMode=yes $W1_VLAN '[ -n \"$CLI\" ]'" 2>/dev/null; then
  debe_ir "$WEB1: cliente SQL contra $BBDD_IP (usuario cnvr)" \
    $ADMIN "ssh -o BatchMode=yes $W1_VLAN '$CLI -h $BBDD_IP -u cnvr -pcnvr2627 cnvr -e \"$SQL\"'"
else
  echo "  [info]  La imagen web no trae cliente SQL. Para la prueba completa: ./scripts/07-cliente-bd.sh"
fi

# -----------------------------------------------------------------------------
sep "P10. Servidor de logs (rsyslog en $LOGS_IP:514)"
MARCA="CNVR-G$GRUPO-$(date +%H%M%S)"
$ADMIN "logger -n $LOGS_IP -P 514 -d 'prueba $MARCA' 2>/dev/null || echo '<14>admin prueba $MARCA' > /dev/udp/$LOGS_IP/514"
sleep 2
debe_ir "El mensaje enviado desde el admin aparece en el servidor de logs" \
  $ADMIN "ssh -o BatchMode=yes logs \"grep -rq '$MARCA' /var/log/remoto/\""
$ADMIN "ssh -o BatchMode=yes logs \"grep -rh '$MARCA' /var/log/remoto/\""

# -----------------------------------------------------------------------------
sep "RESUMEN:  $OKS comprobaciones correctas, $KOS fallos"
[ "$KOS" -eq 0 ] && echo "Todo correcto." || echo "Revisad los [FALLO] con el apartado de problemas de la guía."
