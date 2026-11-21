# Guía paso a paso en el laboratorio · Trabajo final CNVR 26-27 · Grupo 9

Esta guía sustituye al orden de trabajo de la guía PDF. Ya incluye todo lo que se corrigió
en la prueba del laboratorio: la interfaz `e2`, la VLAN `1000`, el sistema de ficheros
`v025-vnxlab`, el XML de VNX arreglado y `--skip-ssl` en el cliente SQL.
**Esos cambios ya están en los ficheros del proyecto: no hay que pegar ningún parche.**

Cómo leerla:

- Cada bloque de código es **un comando por línea**. Copiad y pegad de uno en uno, salvo que
  se indique lo contrario.
- `# -> ...` al final de una línea es lo que debe salir.
- 📸 = haced una captura para la memoria.
- Salvo que se diga otra cosa, todo se ejecuta **en el host**, dentro de la carpeta
  `cnvr-trabajo-final`.

---

## Resumen del día

| Paso | Qué se hace | Qué debe salir |
|---|---|---|
| 1 | Traer el proyecto y comprobar que tiene las correcciones | Los 4 `grep` con los valores indicados |
| 2 | `00-generar-claves.sh` | 4 ficheros en `shared/keys/` |
| 3 | `01-arranque-escenario.sh` + MetalLB + acceso sin contraseña | 3 nodos `Ready` y el Ingress con EXTERNAL-IP |
| 4 | `02-inspeccionar-imagenes.sh` | Los 6 puntos de control |
| 5 | Copiar `shared/` a la carpeta compartida | — |
| 6 | `03-vlan-workers.sh` | `e2.1000` en los 2 workers y Whereabouts `Running` |
| 7 | `04-arranque-lxc.sh` | bbdd escucha en 22 y `0.0.0.0:3306`; logs en 22 y 514 |
| 8 | Terraform por partes | Cada parte con sus comprobaciones |
| 9 | `06-pruebas.sh` | **35 correctas, 0 fallos** |
| 10 | `07-cliente-bd.sh` + `06-pruebas.sh` | **37 correctas, 0 fallos** |
| 11 | P13: `destroy` y volver a desplegar | Vuelve a dar 37 / 0 sin tocar nada |
| 12 | Guardar resultados | Copia en vuestra carpeta personal |

---

## Paso 1 · Traer el proyecto al laboratorio

Abrid una terminal en el host. Trabajad siempre en vuestra carpeta personal (`~`), nunca en
`/mnt/tmp`, que se borra al cerrar la sesión.

**Opción A: con git** (si el repositorio es accesible desde el laboratorio):

```bash
cd ~
git clone https://github.com/MartinLunaAguado/CNVR-Practica-1.git
cd ~/CNVR-Practica-1/cnvr-trabajo-final
chmod +x scripts/*.sh
```

Si ya lo teníais clonado de otro día: `cd ~/CNVR-Practica-1 && git pull && cd cnvr-trabajo-final && chmod +x scripts/*.sh`

**Opción B: con el zip:**

```bash
cd ~
unzip cnvr-trabajo-final-g9.zip
cd ~/cnvr-trabajo-final
chmod +x scripts/*.sh
```

**Comprobad que el proyecto ya tiene las correcciones** (pegad las cuatro líneas):

```bash
grep -nE '^vlan_parent_if|^vlan_id' shared/terraform.tfvars
grep -nE '^VLAN_PARENT_IF|^VLAN_ID' scripts/config.sh
grep -c 'skip-ssl' scripts/06-pruebas.sh
grep -cE 'managed="no"|tag id="1000"|v025-vnxlab|chown syslog|getent hosts' vnx/cnvr-lxc-vlan.xml
```

Debe salir:

| Línea | Resultado esperado |
|---|---|
| 1 | `vlan_parent_if = "e2"` y `vlan_id = 1000` |
| 2 | `VLAN_PARENT_IF=e2` y `VLAN_ID=1000` |
| 3 | `3` |
| 4 | `9` |

Si algo no coincide, tenéis una versión antigua del proyecto: no sigáis, bajad la última.

---

## Paso 2 · Generar las claves SSH

```bash
./scripts/00-generar-claves.sh
ls -l shared/keys/
```

Deben aparecer **4 ficheros**: `admin_web_rsa`, `admin_web_rsa.pub`, `host_admin_rsa`,
`host_admin_rsa.pub` (más `LEEME.txt`). El script no regenera las claves si ya existen.

---

## Paso 3 · Arrancar Kubernetes y la máquina terraform

```bash
./scripts/01-arranque-escenario.sh
```

Tarda varios minutos. Cuando termine:

```bash
kubectl get nodes                          # -> 3 nodos en Ready
kubectl get pods -n ingress-nginx          # -> el controlador en Running
kubectl get pods -n kube-system | grep calico
ssh root@terraform terraform --version
ssh root@terraform ls /shared              # -> los .tf, html/ y keys/
```

📸 `kubectl get nodes`

### 3.0 MetalLB y EXTERNAL-IP del Ingress (aviso del profesor del 20/11)

El Service del Ingress Controller es de tipo **LoadBalancer** y necesita MetalLB para tener
una EXTERNAL-IP. El script 01 ya lo comprueba y lanza `config_metallb` si hace falta, pero
verificadlo:

```bash
kubectl get l2advertisements.metallb.io -n metallb-system   # -> default-l2-advertisement  ["default-pool"]
kubectl get ipaddresspools.metallb.io -n metallb-system     # -> default-pool  true  false  ["10.10.10.20-10.10.10.30"]
kubectl get service -n ingress-nginx                        # -> ingress-nginx-controller con EXTERNAL-IP 10.10.10.2x
```

Si alguno de los dos primeros no devuelve nada, o la EXTERNAL-IP sale `<pending>`:

```bash
cd /mnt/tmp/k8s_lab-calico-v02
sudo vnx -f k8s_lab-calico.xml -x config_metallb
cd -
```

y repetid los tres comandos. 📸 Las tres salidas con la EXTERNAL-IP.

**Si `terraform --version` dice `command not found`** (otro problema de red del lab que
avisaron los profesores):

```bash
cd /mnt/tmp/k8s_lab-calico-v02
sudo vnx -f k8s_lab-terraform.xml -x install-terraform
cd -
ssh root@terraform terraform --version
```

Si sigue fallando, mandad un correo a los profesores: es un problema del laboratorio.

### 3.1 Acceso sin contraseña a los nodos (muy recomendado)

Los scripts entran por SSH como `root` muchas veces. Sin esto os pedirá la contraseña
(`xxxx`) en cada paso.

Primero, si vuestro `~/.ssh/config` apunta todavía a la carpeta del escenario de flannel,
corregidlo (si no existe el fichero, no hace nada):

```bash
[ -f ~/.ssh/config ] && sed -i 's/k8s_lab-flannel-v02/k8s_lab-calico-v02/g' ~/.ssh/config
```

Después copiad vuestra clave a los cuatro nodos (pide `xxxx` una vez por nodo):

```bash
[ -f ~/.ssh/id_rsa ] || ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
for n in k8s-master k8s-worker1 k8s-worker2 terraform; do ssh-copy-id root@$n; done
```

Comprobad que ya no pide contraseña:

```bash
ssh root@terraform hostname                # -> terraform, sin pedir nada
```

---

## Paso 4 · Inspección y puntos de control

Este paso no modifica nada. Guarda la salida en `inspeccion.txt`:

```bash
./scripts/02-inspeccionar-imagenes.sh | tee inspeccion.txt
```

Al final de la salida hay un bloque **"Puntos de control"**. Comprobad esta tabla:

| Qué mirar | Valor esperado | Si sale otra cosa |
|---|---|---|
| Interfaz padre de la VLAN en los workers | `e2 existe (OK)` en los dos | Ver **4.1** |
| `tag id` del XML de la práctica 1.3 | `1000` | Ver **4.2** |
| `filesystem` de ese mismo XML | `...ubuntu64-20.04-v025-vnxlab` | Ver **4.3** |
| EXTERNAL-IP del Ingress Controller | `10.10.10.2x (OK)` | MetalLB no funciona: repetid el **3.0**. Mientras tanto se puede usar el NodePort que sale debajo |
| IP del Pod del Ingress Controller (bloque "Ingress Controller: etiquetas, IP y red") | Una IP de Pod, **distinta** de la del nodo | Ver apartado de problemas de la guía PDF |
| IP del host | `10.10.20.2` | Ver **4.4** |

Revisad también, más arriba en la salida, lo de las imágenes: `gid=1000` en `webuser` y
`adminuser`, el 22 a la escucha en las dos y el 80 en la web.

📸 El bloque de puntos de control.

Si todo coincide, saltad al Paso 5. Si no, corregid con estos comandos **y después
repetid los 4 `grep` del Paso 1 para ver el cambio**.

### 4.1 La interfaz no es `e2`

Mirad en la salida qué interfaz de `k8s-worker1` **no tiene IPv4** y poned su nombre:

```bash
NUEVA=e3        # <-- el nombre real
sed -i -E "s/^vlan_parent_if *=.*/vlan_parent_if = \"$NUEVA\"/" shared/terraform.tfvars
sed -i -E "s/^VLAN_PARENT_IF=.*/VLAN_PARENT_IF=$NUEVA/" scripts/config.sh
```

### 4.2 La VLAN no es `1000`

Hay que cambiarla en tres sitios a la vez:

```bash
N=1000          # <-- el número real
sed -i -E "s/^vlan_id *=.*/vlan_id        = $N/" shared/terraform.tfvars
sed -i -E "s/^VLAN_ID=.*/VLAN_ID=$N/" scripts/config.sh
sed -i -E "s/<tag id=\"[0-9]+\"\/>/<tag id=\"$N\"\/>/g" vnx/cnvr-lxc-vlan.xml
grep 'tag id' vnx/cnvr-lxc-vlan.xml        # -> dos líneas con el número nuevo
```

### 4.3 El sistema de ficheros es otro

```bash
grep filesystem /mnt/tmp/k8s_lab-calico-v02/k8s_lab-vms-vlan.xml     # copiad la ruta
RUTA=/usr/share/vnx/filesystems/LA_RUTA_REAL                          # <-- pegadla aquí
sed -i "s#<filesystem type=\"cow\">[^<]*</filesystem>#<filesystem type=\"cow\">$RUTA</filesystem>#" vnx/cnvr-lxc-vlan.xml
grep filesystem vnx/cnvr-lxc-vlan.xml      # -> dos líneas con la ruta nueva
```

### 4.4 La IP del host no es `10.10.20.2`

```bash
ip -br addr                                # buscad la IP de user_LAN
IPH=10.10.20.2  # <-- la real
sed -i -E "s/^host_ip *=.*/host_ip         = \"$IPH\"/" shared/terraform.tfvars
sed -i -E "s/^HOST_IP=.*/HOST_IP=$IPH/" scripts/config.sh
```

---

## Paso 5 · Copiar el proyecto a la carpeta compartida

La máquina terraform ve `/mnt/tmp/k8s_lab-calico-v02/shared` como `/shared`:

```bash
cp -r shared/. /mnt/tmp/k8s_lab-calico-v02/shared/
ssh root@terraform grep -E '^vlan_parent_if|^vlan_id' /shared/terraform.tfvars   # -> "e2" y 1000
```

> ⚠️ **Regla de oro:** cada vez que cambiéis algo de `shared/` después de este paso, repetid
> el `cp`. Si no, Terraform sigue usando la copia antigua.

---

## Paso 6 · VLAN en los workers, Multus y Whereabouts

```bash
./scripts/03-vlan-workers.sh
```

Comprobad:

```bash
ssh root@k8s-worker1 ip -d link show e2.1000      # -> vlan protocol 802.1Q id 1000
ssh root@k8s-worker2 ip -d link show e2.1000      # -> lo mismo
kubectl get crd | grep -E 'network-attachment|whereabouts'
kubectl get pods -A | grep -Ei 'multus|whereabouts'   # -> todos en Running
```

📸 Las dos salidas de `ip -d link show` y los Pods de Multus y Whereabouts.

> La subinterfaz no sobrevive a un reinicio del worker. Si reiniciáis el escenario, repetid
> este paso.

---

## Paso 7 · Contenedores LXC (bbdd y logs)

```bash
./scripts/04-arranque-lxc.sh
```

Tarda unos minutos (instala paquetes). Al final debe mostrar:

- `bbdd`: IP `10.1.100.21`, escuchando en `:22` y en `0.0.0.0:3306`.
- `logs`: IP `10.1.100.22`, escuchando en `:22` y en `:514` (UDP y TCP).

Comprobaciones a mano:

```bash
sudo lxc-attach -n bbdd -- ip -4 -br addr                        # -> 10.1.100.21/24
sudo lxc-attach -n bbdd -- ss -ltn | grep -E ':(22|3306) '        # -> 0.0.0.0:3306 y :22
sudo lxc-attach -n bbdd -- mysql -e 'SHOW DATABASES; SELECT user,host FROM mysql.user;'
sudo lxc-attach -n logs -- ss -ltnu | grep ':514 '                # -> udp y tcp
sudo lxc-attach -n logs -- ls -ld /var/log/remoto                 # -> dueño syslog adm
sudo lxc-attach -n logs -- ping -c 2 10.1.100.21                  # -> los LXC se ven por la VLAN
```

📸 Las salidas de `ss` y de `SHOW DATABASES`.

Si algo falla:

| Síntoma | Qué hacer |
|---|---|
| `apt-get` no instala nada | Sin Internet por virbr0: `sudo lxc-attach -n bbdd -- ping -c 2 8.8.8.8`. Si responde, relanzad `./scripts/04-arranque-lxc.sh` (se puede repetir) |
| MariaDB no arranca | `sudo lxc-attach -n bbdd -- journalctl -u mariadb -n 30` |
| No aparece el 514 | `sudo lxc-attach -n logs -- systemctl status rsyslog` |

---

## Paso 8 · Terraform por partes

Así se ve el efecto de cada recurso y se pueden sacar las capturas del **antes y el
después** de las NetworkPolicy.

### 8.0 Cómo lanzar terraform sin tropezar

> ⚠️ El fallo de la prueba: al pegar `ssh root@terraform` y los comandos de terraform **en
> bloque**, el resto se ejecutaba en `/root` y salía `No configuration files`.

Usad esta función en el host. Lanza cada orden **dentro de `/shared`** de la máquina
terraform, y así podéis usar `kubectl` en la misma terminal:

```bash
tf() { ssh -t root@terraform "cd /shared && terraform $*"; }
```

> La función solo existe en la terminal donde la escribís. Si abrís otra, volved a pegarla.

Primera vez:

```bash
tf init
tf fmt
tf validate                    # -> Success! The configuration is valid.
```

<details>
<summary>Alternativa: entrar en la máquina terraform</summary>

Escribid **una línea, Enter, esperad, la siguiente**:

```
ssh root@terraform
cd /shared
pwd                            # -> /shared   (si no, no sigáis)
terraform init
```

y en los pasos siguientes usad `terraform` donde la guía pone `tf`. Los `kubectl`, en otra
terminal del host.
</details>

Cada `tf apply` muestra el plan y pregunta `Enter a value:`. Escribid `yes` y Enter.

### 8.1 Secrets y ConfigMaps

Pegad el comando entero (las barras `\` lo unen en una sola línea):

```bash
tf apply \
  -target=kubernetes_secret_v1.ssh_admin_privada \
  -target=kubernetes_secret_v1.ssh_admin_autorizadas \
  -target=kubernetes_secret_v1.ssh_web_autorizadas \
  -target=kubernetes_config_map_v1.plantilla_web \
  -target=kubernetes_config_map_v1.ssh_config_admin
```

Comprobad:

```bash
kubectl get secrets,configmaps
kubectl describe secret ssh-admin-private-key     # -> tamaño de id_rsa, no su contenido
kubectl get secret ssh-web-authorized-keys -o jsonpath='{.data.authorized_keys}' | base64 -d
kubectl get configmap plantilla-web -o yaml       # -> __POD_NAME__ y "Grupo 9"
```

📸 `kubectl get secrets,configmaps`

### 8.2 Redes de Multus

```bash
tf apply -target=kubernetes_manifest.nad_vlan_web -target=kubernetes_manifest.nad_vlan_admin
```

```bash
kubectl get network-attachment-definitions
kubectl get net-attach-def vlan-web -o yaml       # -> "master":"e2.1000"
```

📸 La salida del `-o yaml` donde se ve `e2.1000` y `whereabouts`.

### 8.3 Deployment de los servidores web

```bash
tf apply -target=kubernetes_deployment_v1.web
```

Terraform espera a que los 3 Pods estén listos. Si tarda más de 2 minutos, en **otra
terminal**: `kubectl get pods` y `kubectl describe pod <pod>`.

Guardad el nombre de un Pod en una variable para no copiarlo a mano:

```bash
kubectl get pods -l app=web -o wide
POD=$(kubectl get pods -l app=web -o jsonpath='{.items[0].metadata.name}'); echo $POD
kubectl describe pod $POD | grep -A3 'Init Containers'    # -> genera-index ... Completed
kubectl logs $POD -c genera-index                          # -> index.html generado para web-...
kubectl exec $POD -c web -- ip -4 addr show net1           # -> 10.1.100.1xx
kubectl exec $POD -c web -- ls -ln /home/webuser/.ssh/     # -> authorized_keys  -r--r----- 0 1000
kubectl exec $POD -c web -- curl -s localhost | grep web-  # -> el nombre del Pod
```

📸 `kubectl get pods -l app=web -o wide` y la IP de `net1`.

### 8.4 Service web e Ingress

```bash
tf apply -target=kubernetes_service_v1.web -target=kubernetes_ingress_v1.web
```

```bash
kubectl get svc web-svc                           # -> ClusterIP  8080/TCP
kubectl get endpoints web-svc                     # -> 3 IP, puerto 80
kubectl describe ingress web-ingress              # -> /servers-G9 -> web-svc:8080
```

Probad desde el host. Guardad en `ING` la dirección del Ingress: la EXTERNAL-IP de MetalLB
y, si no la hubiera, worker1 con el NodePort:

```bash
ING=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'); echo $ING
```

Debe salir una IP `10.10.10.2x`. **Solo si sale vacío**, usad el NodePort:

```bash
ING=10.10.10.11:$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}'); echo $ING
```

```bash
curl http://$ING/servers-G9
for i in $(seq 1 9); do curl -s http://$ING/servers-G9 | grep 'class="pod"'; done
curl -s -o /dev/null -w '%{http_code}\n' http://$ING/otra-ruta      # -> 404
```

Deben aparecer los nombres de los **3 Pods** repartidos.

📸 El bucle de `curl` y la página en el navegador: `http://<EXTERNAL-IP>/servers-G9`.

### 8.5 Pod y Service del admin

```bash
tf apply -target=kubernetes_pod_v1.admin -target=kubernetes_service_v1.admin
```

```bash
kubectl get pod admin -o wide                                        # -> NODE k8s-worker1
kubectl get svc admin-svc                                            # -> NodePort 2222:30022/TCP
kubectl get svc admin-svc -o jsonpath='{.spec.externalTrafficPolicy}'; echo   # -> Local
kubectl exec admin -- ls -ln /home/adminuser/.ssh/                   # -> id_rsa, authorized_keys, config de 0:1000
kubectl exec admin -- ip -4 addr show net1                           # -> 10.1.100.10
```

Entrad desde el host:

```bash
ssh -i shared/keys/host_admin_rsa -p 30022 adminuser@10.10.10.11
```

Ya **dentro del admin** (el prompt cambia), uno a uno:

```bash
echo $SSH_CLIENT                  # -> empieza por 10.10.20.2 (se conserva la IP del host)
ping -c 2 10.1.100.21             # -> bbdd responde por la VLAN
ssh bbdd hostname                 # -> bbdd, sin contraseña
ssh logs hostname                 # -> logs
ssh 10.1.100.1xx hostname         # <-- IP de net1 de un web (Paso 8.3): web-..., como webuser
exit
```

📸 `echo $SSH_CLIENT` y los tres `ssh`.

### 8.6 NetworkPolicy: antes y después

> ⚠️ La prueba del **antes** solo se puede hacer **ahora**, antes de aplicarlas.

**Antes** (todo abierto):

```bash
kubectl create namespace pruebas-np
kubectl -n pruebas-np run tester --image=busybox:1.36 --restart=Never --command -- sleep 3600
kubectl -n pruebas-np wait --for=condition=Ready pod/tester --timeout=120s
WEBIP=$(kubectl get pods -l app=web -o jsonpath='{.items[0].status.podIP}'); echo $WEBIP
kubectl -n pruebas-np exec tester -- wget -T 5 -qO- http://$WEBIP | head -5       # -> devuelve la página
ssh root@terraform "timeout 5 bash -c '</dev/tcp/10.10.10.11/30022' && echo ABIERTO || echo BLOQUEADO"   # -> ABIERTO
```

📸 **Antes**: el `wget` con la página y el `ABIERTO`.

Aplicad las tres políticas:

```bash
tf apply \
  -target=kubernetes_network_policy_v1.default_deny_all \
  -target=kubernetes_network_policy_v1.web_desde_ingress \
  -target=kubernetes_network_policy_v1.admin_ssh_desde_host
```

```bash
kubectl get networkpolicy
kubectl describe networkpolicy web-allow-from-ingress-nginx
kubectl describe networkpolicy admin-allow-ssh-from-host
```

**Después** (repetid las mismas pruebas):

```bash
kubectl -n pruebas-np exec tester -- wget -T 5 -qO- http://$WEBIP          # -> download timed out
ssh root@terraform "timeout 5 bash -c '</dev/tcp/10.10.10.11/30022' && echo ABIERTO || echo BLOQUEADO"   # -> BLOQUEADO
curl -s -o /dev/null -w '%{http_code}\n' http://$ING/servers-G9      # -> 200 (el Ingress sigue)
ssh -i shared/keys/host_admin_rsa -p 30022 adminuser@10.10.10.11 'echo dentro'  # -> dentro (el host sigue)
```

📸 **Después**: timeout, `BLOQUEADO`, `200` y `dentro`.

Borrad el Pod de pruebas (espera a que desaparezca; `06-pruebas.sh` usa el mismo nombre):

```bash
kubectl delete namespace pruebas-np
```

### 8.7 Aplicar el resto y revisar

```bash
tf apply                                   # crea lo que falte y muestra los outputs
tf apply -refresh-only -auto-approve       # vuelve a leer las IP de la VLAN
tf output                                  # -> web_pods_ip_vlan con 3 IP, sin "pendiente"
tf state list                              # -> todos los recursos gestionados
tf plan                                    # -> No changes.
```

📸 `tf output` y `No changes`.

**Escalado** ("aplicación escalable"):

```bash
tf apply -var=num_replicas=5
kubectl get pods -l app=web -o wide        # -> 5 Pods, cada uno con su IP
tf apply -refresh-only -auto-approve -var=num_replicas=5
tf output web_pods_ip_vlan                 # -> 5 IP en la VLAN
```

📸 Los 5 Pods y sus 5 IP.

Volver a 3:

```bash
tf apply
tf apply -refresh-only -auto-approve       # si no, el output sigue mostrando 5 Pods
tf output web_pods_ip_vlan                 # -> 3 IP
kubectl get pods -l app=web                # -> 3 Pods
```

---

## Paso 9 · Pruebas automáticas

```bash
./scripts/06-pruebas.sh | tee pruebas.txt
```

Resultado esperado: **`RESUMEN: 35 comprobaciones correctas, 0 fallos`**.

En P9 aparecerán dos `[info]` diciendo que las imágenes no traen cliente SQL: es normal,
se arregla en el paso siguiente.

📸 Cada bloque P1…P10 y el resumen.

---

## Paso 10 · Cliente SQL en los Pods (prueba completa de la BD)

```bash
./scripts/07-cliente-bd.sh
./scripts/06-pruebas.sh | tee pruebas.txt
```

Resultado esperado: **`RESUMEN: 37 comprobaciones correctas, 0 fallos`**.

📸 El bloque P9 con las inserciones y el resumen.

> ⚠️ El cliente se instala a mano dentro de los Pods, así que **se pierde si un Pod se
> recrea**. Si escaláis o hacéis `destroy`, volved a lanzar `07-cliente-bd.sh` antes de las
> pruebas.

**Consultas SQL a mano** (para la memoria o la defensa). Siempre con `--skip-ssl`:

Desde el admin:

```bash
ssh -i shared/keys/host_admin_rsa -p 30022 adminuser@10.10.10.11
```

```bash
mysql --skip-ssl -h 10.1.100.21 -u cnvr -pcnvr2627 cnvr -e "INSERT INTO accesos(origen,mensaje) VALUES (USER(), 'prueba admin'); SELECT * FROM accesos;"
```

Desde un servidor web (seguís dentro del admin):

```bash
ssh 10.1.100.1xx                  # <-- IP de net1 de un web
mysql --skip-ssl -h 10.1.100.21 -u cnvr -pcnvr2627 cnvr -e 'SELECT * FROM accesos'
exit
```

Administración de MariaDB desde el admin (por SSH al contenedor):

```bash
ssh bbdd "mysql -e 'SHOW DATABASES; SELECT user,host FROM mysql.user;'"
exit
```

---

## Paso 11 · P13: el despliegue es repetible

Destruid todo lo de Terraform (pide `yes`):

```bash
tf destroy
kubectl get all,networkpolicy,net-attach-def      # -> solo queda service/kubernetes
```

> Si `tf destroy` termina con `Error: Pod admin still exists (Running)`, esperad un rato
> hasta que `kubectl get pod admin` diga `NotFound` y repetid `tf destroy`.

📸 El `Destroy complete!` y el clúster vacío.

Volved a desplegarlo todo sin tocar nada:

```bash
./scripts/desplegar-todo.sh --sin-k8s
./scripts/07-cliente-bd.sh
./scripts/06-pruebas.sh | tee pruebas-p13.txt
```

`desplegar-todo.sh --sin-k8s` no regenera las claves, vuelve a copiar `shared/`, rehace la
VLAN, **reconfigura** los LXC (si ya están arrancados no los vuelve a crear) y lanza
`terraform apply` completo.

Resultado esperado: **37 correctas, 0 fallos** (35 si no lanzáis `07-cliente-bd.sh`).

📸 El resumen final.

---

## Paso 12 · Antes de iros

`/mnt/tmp` se borra al cerrar la sesión. Lo vuestro (proyecto, `inspeccion.txt`,
`pruebas*.txt`) ya está en `~`. Para guardar también el estado de Terraform:

```bash
mkdir -p ~/cnvr-backup && cp -r /mnt/tmp/k8s_lab-calico-v02/shared/. ~/cnvr-backup/ && rm -rf ~/cnvr-backup/.terraform
```

Si queréis dejarlo todo limpio (hace copia, `terraform destroy` y borra los LXC y la VLAN):

```bash
./scripts/99-borrar.sh
```

---

## Chuleta de avisos

| Situación | Qué hacer |
|---|---|
| `No configuration files` en terraform | Estáis en `/root`. Usad la función `tf` o `cd /shared` antes |
| Cambiáis algo de `shared/` después del Paso 5 | `cp -r shared/. /mnt/tmp/k8s_lab-calico-v02/shared/` |
| Tras volver a 3 réplicas los outputs siguen con 5 Pods | `tf apply -refresh-only -auto-approve` |
| `mysql` falla por TLS/SSL desde un Pod | Añadid `--skip-ssl` |
| Tras escalar o `destroy`, P9 vuelve a dar `[info]` | `./scripts/07-cliente-bd.sh` otra vez |
| Queréis la captura del "antes" de las NetworkPolicy | Solo se puede antes de aplicarlas: despliegue por partes (Paso 8.6) |
| Abrís una terminal nueva | Volved a definir `tf() { ... }` y, si la usáis, `ING=...` |
| El Ingress no tiene EXTERNAL-IP (`<pending>`) | `sudo vnx -f k8s_lab-calico.xml -x config_metallb` en `/mnt/tmp/k8s_lab-calico-v02` (Paso 3.0) |
| `terraform: command not found` | `sudo vnx -f k8s_lab-terraform.xml -x install-terraform`; si sigue, correo a los profesores |
| Se ha reiniciado un worker | `./scripts/03-vlan-workers.sh` |
| `tf destroy` da `Pod admin still exists` | Esperad un rato, comprobad con `kubectl get pod admin` que ya no está y repetid `tf destroy`. Si no desaparece: `kubectl delete pod admin --grace-period=0 --force` |

**Atajo:** si un día solo queréis tenerlo todo desplegado, después del Paso 2 basta con
`./scripts/desplegar-todo.sh` (y luego `07-cliente-bd.sh` y `06-pruebas.sh`). Para la
memoria es mejor ir paso a paso por las capturas del antes y el después.

---

## Para la memoria: problemas encontrados y soluciones

1. **Interfaz y VLAN distintas a las de la guía** (`e2` y VLAN `1000`, no `eth2` y `100`).
   Se detectó con `02-inspeccionar-imagenes.sh` y con el XML de la práctica 1.3
   (`k8s_lab-vms-vlan.xml`).
2. **`VlanNet` sin `managed="no"`**: la red la crea el escenario de Kubernetes y VNX no debe
   gestionarla. También había que usar el sistema de ficheros del laboratorio
   (`...ubuntu64-20.04-v025-vnxlab`).
3. **`filetree` copia carpetas enteras**: los `exec` buscaban los ficheros en
   `/root/conf/` en lugar de `/root/conf/ssh/`, `/root/conf/bbdd/`… (`cp: cannot stat`).
4. **La imagen LXC traía MySQL 8.0, incompatible con MariaDB.** Se diagnosticó con
   `apt-get install -s -o Debug::pkgProblemResolver=yes mariadb-server`.
5. **Datos de MySQL en `/var/lib/mysql`**: MariaDB no arrancaba (`found previous version
   5.7`). Se borran, solo si MySQL estaba instalado, para que la configuración se pueda
   repetir.
6. **Carrera con el DHCP**: `apt-get` fallaba en `logs` porque aún no tenía red. Se añadió
   una espera a la resolución DNS (`getent hosts archive.ubuntu.com`).
7. **rsyslog sin permisos**: `Permission denied` al crear `/var/log/remoto/admin.log`,
   porque rsyslog se ejecuta como el usuario `syslog`. Solución: `chown syslog:adm
   /var/log/remoto`.
8. **El cliente SQL de la imagen web exige TLS** y MariaDB 10.3 no lo tiene configurado.
   Se resolvió con `--skip-ssl`; activar TLS en MariaDB queda como mejora posible.
9. **Terraform lanzado fuera de `/shared`**: al pegar los comandos en bloque tras
   `ssh root@terraform`, se ejecutaban en `/root` (`No configuration files`). Se resolvió
   lanzándolos de uno en uno o con `ssh root@terraform "cd /shared && terraform ..."`.
10. **`terraform destroy` falla con `Error: Pod admin still exists (Running)`** (prueba P13).
    Terraform pide borrar el Pod admin y deja de esperar antes de que Kubernetes termine de
    eliminarlo. Se resolvió solo: tras esperar un rato el Pod desapareció y, al repetir
    `terraform destroy`, se borró el resto de recursos (`Destroy complete!`), porque
    Terraform solo elimina lo que queda. Si no desaparece, se puede forzar con
    `kubectl delete pod admin --grace-period=0 --force`.
11. **El Ingress Controller no tenía EXTERNAL-IP** (incidencia del laboratorio avisada por
    los profesores el 20/11). Su Service es LoadBalancer y depende de MetalLB, cuyas imágenes
    (en quay.io) no se podían descargar desde la red del laboratorio. Mientras tanto se
    accedió por el NodePort del Ingress en worker1 (`10.10.10.11:30097`). Con el escenario
    regenerado, el script 01 comprueba MetalLB y lanza `config_metallb` si hace falta, y el
    acceso pasa a ser la EXTERNAL-IP (`10.10.10.20-30`).
12. **Base de datos**: la imagen LXC traía MySQL 8.0 y elegimos MariaDB. Los profesores
    aclararon después que valía cualquier SGBD instalable como paquete; mantuvimos MariaDB
    porque, tras quitar MySQL 8.0 (puntos 4 y 5), funcionaba y pasaba todas las pruebas.
