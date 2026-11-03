# Guía paso a paso del trabajo final de CNVR 2026-27

**Despliegue automático de una aplicación escalable sobre Kubernetes con Terraform**
Martín Luna Guado y Brayan Guarachi Apaza

---

## 0. Antes de empezar: qué hay que hacer y qué os doy

### 0.1 Qué pide el enunciado

Hay que montar la topología de la Figura 1 del enunciado **solo con ficheros de Terraform, scripts y ficheros de configuración**, de forma que se pueda desplegar automáticamente:

| Pieza | Qué es | Dónde está en el proyecto |
|---|---|---|
| S1, S2, S3 | 3 Pods Nginx creados con un **Deployment**, con una página que muestra el nombre del Pod | `shared/web-deployment.tf`, `shared/configmap.tf`, `shared/html/index.html.tpl` |
| admin | 1 Pod de administración, fijado en `k8s-worker1`, al que se entra por SSH | `shared/admin-pod.tf` |
| Svc Web | Service **ClusterIP** 8080 → 80 | `shared/services.tf` |
| Svc admin | Service **NodePort** 2222 → 22, con `externalTrafficPolicy: Local` | `shared/services.tf` |
| Ingress | Ruta `/servers-GX` → Svc Web | `shared/ingress.tf` |
| VLAN | Red compartida entre Pods (vía **Multus**) y contenedores LXC (vía **VNX**) | `shared/multus.tf`, `scripts/02-vlan-workers.sh`, `vnx/cnvr-lxc-vlan.xml` |
| BBDD y logs | 2 contenedores LXC en VNX: MariaDB y rsyslog | `vnx/cnvr-lxc-vlan.xml`, `vnx/conf/` |
| Claves SSH | Repartidas con **Secrets** | `shared/secrets.tf`, `scripts/00-generar-claves.sh` |
| Seguridad | 3 **NetworkPolicy**: denegar todo, web solo desde el Ingress Controller, admin solo SSH desde el host | `shared/network-policies.tf` |

### 0.2 El proyecto del año pasado: para qué sirve y para qué no

El zip del año pasado (Grupo 21) está hecho sobre **OpenStack** (VMs, Octavia, FWaaS, cloud-init). **Su código no os sirve**, porque este año todo es Kubernetes. Sí os sirve para:

- La **estructura**: scripts de arranque y borrado, README, memoria con una sección de pruebas por requisito.
- El **estilo de la memoria**: requisito → cómo se ha configurado → prueba con captura. Os propongo la misma estructura en el apartado 9.
- La idea de las **pruebas negativas** (demostrar que lo que *no* debe funcionar no funciona). Este año son igual de importantes por las NetworkPolicy.

### 0.3 Lo que no puedo saber desde aquí (comprobadlo en el laboratorio)

He dejado todo **parametrizado** en `shared/terraform.tfvars` y `scripts/config.sh`. Antes de desplegar, confirmad estos datos y cambiadlos si hace falta. Es lo primero que tenéis que hacer en el laboratorio:

| # | Dato | Cómo averiguarlo | Variable |
|---|---|---|---|
| 1 | Vuestro número de grupo | — | `grupo` / `GRUPO` |
| 2 | Nombre de las imágenes web y admin "que se proporcionarán" | Moodle / profesor | `imagen_web`, `imagen_admin` |
| 3 | Directorio desde el que Nginx sirve en la imagen web | `kubectl run t --image=<imagen_web> --rm -it -- cat /etc/nginx/conf.d/default.conf` (buscar `root`) | `web_root` |
| 4 | Interfaz de los workers conectada a **VlanNet** | `ssh root@k8s-worker1 ip -br a` (será la que no tiene IP de k8s_LAN ni de virbr0) | `vlan_parent_if` / `VLAN_PARENT_IF` |
| 5 | VLAN ID que usa el escenario `k8s_lab-vms-vlan.xml` de la P1.3 | abrir ese XML y buscar `<tag id=...>` | `vlan_id` / `VLAN_ID` |
| 6 | ¿Está instalado Multus? ¿Y Whereabouts? | `kubectl get pods -A \| grep -E 'multus\|whereabouts'` | (el script 02 instala Whereabouts si falta) |
| 7 | Etiquetas de los Pods del Ingress Controller | `kubectl get pods -n ingress-nginx --show-labels` | `ingress_controller_labels` |
| 8 | Cómo se expone el Ingress Controller (NodePort o LoadBalancer) | `kubectl get svc -n ingress-nginx` | (lo detecta `05-pruebas.sh`) |
| 9 | Ruta del filesystem LXC y sintaxis de VLAN en VNX | copiar de `k8s_lab-vms-vlan.xml` | `vnx/cnvr-lxc-vlan.xml` |

> **Errata en el enunciado (apartado 2, punto 5).** El texto dice que a los servidores web se les da la clave *privada* y al admin la *pública*. Es al revés. Quien inicia la conexión SSH (el **admin**) necesita la **privada**, y los equipos a los que se conecta (**web**, BBDD, logs) necesitan la **pública** en `authorized_keys`. Lo he implementado así y conviene explicarlo en la memoria. Si queréis, confirmadlo con el profesor.

---

## 1. Conceptos que tenéis que entender (y explicar en la memoria)

**Terraform (IaC).** Describís el estado deseado en ficheros `.tf` (lenguaje HCL). Terraform compara ese estado con lo que existe en el clúster y crea, modifica o borra lo necesario. Los comandos son los de la P1.4: `init` (descarga el proveedor), `validate` (sintaxis), `plan` (vista previa), `apply` (aplica), `destroy` (borra) y `state list` / `state show` (lo que gestiona). Terraform carga **todos** los `.tf` de la carpeta como si fueran uno solo. Repartirlos en varios ficheros es solo por orden.

**Dependencias.** Cuando un recurso usa un atributo de otro (por ejemplo, el Deployment usa `kubernetes_manifest.nad_vlan_web.manifest.metadata.name`), Terraform sabe que el segundo debe crearse antes. Por eso no hay casi ningún `depends_on`.

**Multus.** Por defecto, cada Pod tiene una sola interfaz (`eth0`) gestionada por Calico. Multus es un "meta-CNI" que permite añadir interfaces extra. Cada red extra se describe en un recurso **NetworkAttachmentDefinition (NAD)**, y el Pod la pide con la anotación `k8s.v1.cni.cncf.io/networks: <nombre-NAD>`. La interfaz extra aparece como **`net1`**.

**macvlan + VLAN.** En cada worker se crea una subinterfaz VLAN (`eth2.100`), que etiqueta con el ID 100 todo lo que sale por ella. El plugin `macvlan` crea dentro del Pod una interfaz "hija" de `eth2.100` con su propia MAC. Así, el Pod queda conectado directamente a la VLAN 100 de VlanNet, que es la misma VLAN a la que VNX conecta los LXC. Resultado: Pods y LXC están en la misma red L2, `10.1.100.0/24`.

**IPAM (quién da la IP en net1).**
- Web (3 réplicas creadas por un Deployment) → **whereabouts**. Reparte IPs de un rango a todo el clúster sin repetir. Con `host-local`, cada nodo llevaría su propia cuenta y dos Pods en nodos distintos podrían recibir la misma IP.
- Admin (un único Pod) → **static**, con IP fija `10.1.100.10`. Así siempre sabéis dónde está.

**NetworkPolicy (con Calico).**
- Sin ninguna política, todo está permitido. En cuanto una política selecciona un Pod para Ingress o Egress, en ese sentido solo se permite lo que digan las reglas.
- Son **aditivas**: lo permitido es la unión de todas las políticas.
- Son **stateful**: las respuestas de una conexión permitida vuelven solas.
- **Solo actúan sobre `eth0` (Calico)**. El tráfico por `net1` (la VLAN de Multus) no pasa por Calico, así que no le afectan. Por eso el admin puede hacer SSH a los web por la VLAN aunque haya un "deny-all". Explicadlo en la memoria, porque es una pregunta típica.

**`externalTrafficPolicy: Local` y la IP origen.** Cuando un cliente se conecta a `IP_nodo:NodePort`, kube-proxy hace DNAT hacia la IP del Pod.
- Con `Cluster` (por defecto), si el Pod está en otro nodo, hace también **SNAT**: el Pod ve como origen la IP de un nodo y no la del cliente. La política `ipBlock: 10.10.20.2/32` no coincidiría nunca.
- Con `Local`, kube-proxy **solo envía a Pods del mismo nodo y no hace SNAT**: el Pod ve `10.10.20.2`. Por eso el admin debe estar en `k8s-worker1` (`nodeSelector`) y hay que conectarse a la IP de `k8s-worker1` (`10.10.10.11`).

Recorrido completo: host `10.10.20.2` → r1 → `10.10.10.11:30022` → DNAT a `IP_Pod_admin:22` (sin SNAT) → Calico comprueba `ipBlock 10.10.20.2/32` y puerto 22 → se permite.

---

## 2. Estructura del proyecto

```
cnvr-trabajo-final/
├── GUIA.md                      ← esta guía
├── shared/                      ← se copia a /mnt/tmp/k8s_lab-calico-v02/shared (= /shared en la VM terraform)
│   ├── k8s-provider.tf          proveedor kubernetes 2.23.0
│   ├── variables.tf             definición de variables
│   ├── terraform.tfvars         VALORES (¡revisar!)
│   ├── locals.tf                etiquetas y valores calculados
│   ├── secrets.tf               claves SSH → Secrets
│   ├── multus.tf                NetworkAttachmentDefinitions (kubernetes_manifest)
│   ├── configmap.tf             plantilla HTML → ConfigMap
│   ├── html/index.html.tpl      plantilla con __POD_NAME__
│   ├── web-deployment.tf        Deployment web (initContainers + volúmenes)
│   ├── admin-pod.tf             Pod admin
│   ├── services.tf              Service ClusterIP y NodePort
│   ├── ingress.tf               Ingress /servers-GX
│   ├── network-policies.tf      3 NetworkPolicy
│   ├── outputs.tf               salidas (nombres, IPs VLAN...)
│   └── keys/                    aquí se generan las claves
├── vnx/
│   ├── cnvr-lxc-vlan.xml        escenario VNX con LXC bbdd y logs
│   └── conf/{ssh,bbdd,logs}/    ficheros que se copian con filetree
└── scripts/
    ├── config.sh                parámetros comunes
    ├── 00-generar-claves.sh     (host)
    ├── 01-arranque-escenario.sh (host)
    ├── 02-vlan-workers.sh       (host)
    ├── 03-arranque-lxc.sh       (host)
    ├── 04-terraform-deploy.sh   (VM terraform)
    ├── 05-pruebas.sh            (host)
    └── 99-borrar.sh             (host)
```

> **Recordad:** `/mnt/tmp` se borra. Trabajad en vuestra carpeta personal, copiad a `shared` (lo hace el script 01) y usad git o una copia de seguridad (lo hace el script 99).

---

## 3. Paso 1: preparar el proyecto y generar las claves (host)

```bash
cd ~ && unzip cnvr-trabajo-final.zip && cd cnvr-trabajo-final
chmod +x scripts/*.sh
nano shared/terraform.tfvars     # grupo, imágenes, interfaz VLAN... (tabla 0.3)
nano scripts/config.sh           # mismos valores
./scripts/00-generar-claves.sh
```

**Qué hace `00-generar-claves.sh`:**
- Crea `shared/keys/admin_key` y `admin_key.pub` (ed25519, sin contraseña). Con este par, el admin entra en los web y en los LXC.
- Crea `shared/keys/host_key` y `host_key.pub`. Con este par, vosotros entráis desde el host al admin.
- Copia `admin_key.pub` a `vnx/conf/ssh/authorized_keys`, para que VNX la meta en los LXC.

¿Por qué dos pares? Por buena práctica: la clave privada que vive dentro de un Pod (la del admin) no debería servir para entrar al propio admin desde fuera.

---

## 4. Paso 2: arrancar el escenario Kubernetes y la VM terraform (host)

```bash
./scripts/01-arranque-escenario.sh
```

Hace exactamente lo del apartado 3 de la P1.4:

1. `get-k8s-calico` y `start-k8s-calico`: clúster con master, worker1, worker2 y Calico.
2. Crea la VM `terraform` e instala Terraform (`-x install-terraform`).
3. `get-master-kubeconf` y `set-terraform-kubeconf`: deja `~/.kube/config` en el host y en la VM terraform.
4. Copia `shared/` a `/mnt/tmp/k8s_lab-calico-v02/shared`.

**Comprobad:**
```bash
kubectl get nodes                  # 3 nodos Ready
kubectl get pods -n ingress-nginx  # controlador Ingress Running
ssh root@terraform terraform --version
```

Ahora rellenad los datos 4, 6, 7 y 8 de la tabla 0.3. Si cambiáis algo en `shared/`, volved a copiarlo con `cp -r shared/. /mnt/tmp/k8s_lab-calico-v02/shared/`.

---

## 5. Paso 3: VLAN en los workers y Multus (host). Apartado 2.1 y 2.2

```bash
./scripts/02-vlan-workers.sh
```

En cada worker ejecuta:
```bash
ip link add link eth2 name eth2.100 type vlan id 100
ip link set eth2 up && ip link set eth2.100 up
```
Es lo mismo que hicisteis a mano en la P1.3. Además comprueba que existe la CRD de Multus e instala Whereabouts si no está.

**Comprobad:**
```bash
ssh root@k8s-worker1 ip -d link show eth2.100   # "vlan protocol 802.1Q id 100"
kubectl get crd | grep -E 'network-attachment|whereabouts'
```

> Si en la P1.3 la VLAN se configuró de otra forma (por ejemplo, con otro plugin), mirad cómo era y adaptad `multus.tf`. La idea es la misma: una NAD cuyo `master` es la subinterfaz VLAN.

---

## 6. Paso 4: contenedores LXC con VNX (host). Apartado 2.6

1. **Abrid antes `k8s_lab-vms-vlan.xml`** (en `/mnt/tmp/k8s_lab-calico-v02`) y comparad con `vnx/cnvr-lxc-vlan.xml`: la ruta de `<filesystem>`, la línea `<net name="VlanNet" .../>` y el bloque `<vlan><tag id="..."/></vlan>`. Si difieren, copiad lo del laboratorio, que es lo que funciona allí.
2. Ejecutad:
```bash
./scripts/03-arranque-lxc.sh
```

**Qué hace el XML:**
- Dos LXC, `bbdd` (`10.1.100.21`) y `logs` (`10.1.100.22`). Cada uno tiene una interfaz en VlanNet etiquetada en la VLAN 100 y otra en `virbr0` (por DHCP), que solo sirve para que `apt-get` tenga Internet.
- **`<filetree seq="configurar">`** copia las carpetas `conf/ssh`, `conf/bbdd` y `conf/logs` del host a `/root/conf/` del contenedor.
- **`<exec seq="configurar">`** ejecuta los comandos en orden:
  - instala `mariadb-server` / `rsyslog` y `openssh-server`;
  - coloca `authorized_keys` con permisos 700/600 y desactiva el login con contraseña;
  - BBDD: copia `60-cnvr.cnf` (`bind-address = 0.0.0.0`, porque por defecto MariaDB solo escucha en localhost; es el mismo problema que tuvo el grupo del año pasado) y ejecuta `init.sql`. Este script crea la BD `cnvr`, el usuario `cnvr` (contraseña `cnvr2627`) que solo puede entrar desde `10.1.100.%` y una tabla `accesos`;
  - logs: copia `10-remoto.conf`, que hace que rsyslog escuche en UDP/TCP 514 y guarde cada origen en `/var/log/remoto/<host>.log`.

**Comprobad:**
```bash
sudo lxc-attach -n bbdd -- ss -ltnp | grep 3306    # 0.0.0.0:3306
sudo lxc-attach -n logs -- ss -lunp | grep 514
sudo lxc-attach -n bbdd -- ip a                     # 10.1.100.21 en eth1
```

---

## 7. Paso 5: desplegar con Terraform, fichero a fichero

Podéis lanzarlo todo de golpe con `04-terraform-deploy.sh`. **Para aprender y para la memoria, os recomiendo ir por partes con `-target`**, como en la P1.4. Así veis el efecto de cada recurso, sobre todo el antes y el después de las NetworkPolicy.

```bash
ssh root@terraform
cd /shared
terraform init
terraform validate
```

### 7.1 Secrets y ConfigMap (`secrets.tf`, `configmap.tf`)

```bash
terraform apply -target=kubernetes_secret_v1.ssh_admin_privada \
                -target=kubernetes_secret_v1.ssh_web_autorizadas \
                -target=kubernetes_secret_v1.ssh_admin_autorizadas \
                -target=kubernetes_config_map_v1.plantilla_web
kubectl get secrets,configmaps
kubectl get configmap plantilla-web -o yaml   # veréis __POD_NAME__
```

**Puntos clave:**
- `file("keys/admin_key")` lee el fichero en el momento del `apply`. En `data` se pone el texto en claro y el proveedor lo pasa a base64.
- El Secret del admin incluye también un `config` de cliente SSH (`StrictHostKeyChecking accept-new`) para que no pregunte "yes/no" la primera vez.
- `templatefile()` rellena `${grupo}` en la plantilla. Los marcadores `__POD_NAME__`, `__NODE_NAME__` y `__POD_IP__` no son sintaxis de Terraform y llegan intactos al ConfigMap.

### 7.2 NetworkAttachmentDefinitions (`multus.tf`)

```bash
terraform apply -target=kubernetes_manifest.nad_vlan_web -target=kubernetes_manifest.nad_vlan_admin
kubectl get network-attachment-definitions
kubectl get net-attach-def vlan-web -o yaml
```

**Puntos clave:**
- No existe un recurso `kubernetes_network_attachment_definition`, así que se usa **`kubernetes_manifest`**: es el YAML de Kubernetes escrito en HCL.
- `spec.config` es un **string JSON**; por eso se usa `jsonencode({...})`.
- `kubernetes_manifest` consulta la API durante `plan`. Si Multus no está instalado, falla aquí con "no matches for kind NetworkAttachmentDefinition".

### 7.3 Deployment web (`web-deployment.tf`). Apartado 3

```bash
terraform apply -target=kubernetes_deployment_v1.web
kubectl get pods -l app=web -o wide
kubectl describe pod <pod-web>          # Init Containers: genera-index, prepara-ssh -> Completed
kubectl logs <pod-web> -c genera-index  # "index.html generado para web-xxxx"
kubectl exec <pod-web> -c web -- cat /usr/share/nginx/html/index.html
kubectl exec <pod-web> -c web -- ip a show net1    # IP 10.1.100.1xx
```

Cómo funciona por dentro (**opción B, initContainer**):

1. Kubernetes crea el Pod. Multus ve la anotación `k8s.v1.cni.cncf.io/networks: vlan-web` y añade `net1`.
2. Se ejecuta el **initContainer `genera-index`** (busybox):
   - recibe `POD_NAME`, `NODE_NAME` y `POD_IP` mediante la **Downward API** (`value_from.field_ref`);
   - lee `/plantilla/index.html` del volumen **ConfigMap (read_only)**;
   - hace `sed s/__POD_NAME__/$POD_NAME/` y escribe en `/html/index.html`, que es el volumen **emptyDir** compartido.
3. Se ejecuta el **initContainer `prepara-ssh`**: copia `authorized_keys` del Secret a otro emptyDir que luego se monta en `/root/.ssh` del contenedor web, con permisos 700/600. Este paso es necesario porque sshd rechaza claves si los permisos no son estrictos y un volumen Secret montado directamente no siempre los cumple.
4. Arranca el contenedor **`web`** con el emptyDir `html` montado en `web_root`. Nginx sirve la página ya personalizada.

¿Por qué opción B y no sidecar? El nombre del Pod no cambia durante su vida, así que basta generarlo una vez antes de que arranque Nginx. Es más simple y no deja un contenedor extra consumiendo recursos. Un sidecar tendría sentido si la página tuviera que regenerarse periódicamente. Comentad esta decisión en la memoria.

### 7.4 Services e Ingress (`services.tf`, `ingress.tf`). Apartado 4

```bash
terraform apply -target=kubernetes_service_v1.web -target=kubernetes_ingress_v1.web
kubectl get svc web-svc          # ClusterIP, 8080/TCP
kubectl get ingress web-ingress
kubectl -n ingress-nginx get svc # anotad el NodePort del puerto 80
curl http://10.10.10.11:<NodePort_ingress>/servers-G<X>   # desde el host
```

Lanzad el `curl` varias veces: debe cambiar el nombre del Pod. El balanceo lo hace el Ingress Controller entre los endpoints del Service.

**`rewrite-target: /`:** el cliente pide `/servers-GX`, pero en el web root de Nginx no hay ningún fichero con ese nombre. El controlador reescribe la ruta a `/` antes de reenviar la petición. Sin esa anotación obtendríais un 404 servido por Nginx.

### 7.5 Pod y Service admin (`admin-pod.tf`, `services.tf`)

```bash
terraform apply -target=kubernetes_pod_v1.admin -target=kubernetes_service_v1.admin
kubectl get pod admin -o wide           # NODE = k8s-worker1
kubectl get svc admin-svc               # 2222:30022/TCP
ssh -i shared/keys/host_key -p 30022 root@10.10.10.11   # desde el host
```

### 7.6 NetworkPolicy (`network-policies.tf`). Apartado 5. Probad antes y después

**Antes** de aplicarlas, haced estas pruebas y guardad captura de que *funcionan*:
```bash
ssh root@k8s-master curl -s -m5 http://<IP_eth0_pod_web>      # responde
ssh root@k8s-master "timeout 5 bash -c '</dev/tcp/10.10.10.11/30022' && echo ABIERTO"
```

Aplicad las políticas:
```bash
terraform apply -target=kubernetes_network_policy_v1.default_deny_all \
                -target=kubernetes_network_policy_v1.web_desde_ingress \
                -target=kubernetes_network_policy_v1.admin_ssh_desde_host
kubectl get networkpolicy
kubectl describe networkpolicy web-allow-from-ingress-nginx
```

**Después**, las mismas pruebas desde `k8s-master` deben **fallar**. En cambio, el `curl` al Ingress y el `ssh -p 30022` desde el host deben **seguir funcionando**.

Explicación de cada política:

1. **`default-deny-all`**: `pod_selector {}` selecciona todos los Pods del namespace y `policy_types = [Ingress, Egress]` sin reglas. Todo queda bloqueado en `eth0`.
2. **`web-allow-from-ingress-nginx`**: Pods `app=web`, Ingress TCP/80. El origen se define con `namespace_selector` (`kubernetes.io/metadata.name: ingress-nginx`) **y** `pod_selector` (etiquetas del controlador) **en el mismo bloque `from`**, lo que significa AND. Si los pusierais en dos bloques `from` separados sería OR, y se permitiría cualquier Pod del namespace ingress-nginx *o* cualquier Pod con esas etiquetas en vuestro namespace.
   El Ingress Controller no pasa por la ClusterIP: se conecta **directamente a las IPs de los Pods** (endpoints). Por eso el origen que ve Calico es el Pod del controlador y el puerto es 80, no 8080. La respuesta vuelve gracias al comportamiento stateful, aunque el egress de los web esté denegado.
3. **`admin-allow-ssh-from-host`**: Pod `app=admin`, Ingress TCP/22 desde `ipBlock 10.10.20.2/32`. Funciona gracias a `externalTrafficPolicy: Local` + `nodeSelector` (ver apartado 1).

### 7.7 Todo junto y outputs

```bash
terraform apply                       # aplica lo que falte (outputs incluidos)
terraform apply -refresh-only -auto-approve
terraform output
terraform output -json web_pods_ip_vlan
terraform state list
```

`web_pods_ip_vlan` lee la anotación `k8s.v1.cni.cncf.io/network-status` que escribe Multus en cada Pod. Así sabéis la IP VLAN de cada web sin entrar en ellos. Si sale "pendiente", repetid el `-refresh-only`.

---

## 8. Paso 6: pruebas (Apartado 2.7). Qué ejecutar y qué capturar

`./scripts/05-pruebas.sh` lanza todas las pruebas automáticamente. Esta es la lista para la memoria:

| # | Prueba | Comando | Resultado esperado |
|---|---|---|---|
| P1 | Recursos creados | `kubectl get deploy,pods,svc,ingress,networkpolicy,net-attach-def -o wide` | 3 web + admin Running; admin en worker1 |
| P2 | Interfaces Multus | `kubectl exec <pod> -- ip a show net1` | IP `10.1.100.x/24` |
| P3 | Página personalizada y balanceo | `for i in $(seq 9); do curl -s http://10.10.10.11:<NP>/servers-GX \| grep pod; done` | Aparecen los 3 nombres de Pod |
| P4 | SSH host → admin | `ssh -i keys/host_key -p 30022 root@10.10.10.11` | Entra **sin contraseña** |
| P4b | Se conserva la IP origen | dentro del admin: `ss -tn \| grep :22` | Peer `10.10.20.2` (si veis otra IP, r1 hace NAT: avisad al profesor) |
| P5 | SSH al admin desde otro origen | desde k8s-master o terraform: `ssh -p 30022 root@10.10.10.11` | **Timeout** |
| P5b | SSH por el otro nodo | `ssh -p 30022 root@10.10.10.12` (worker2) | **Falla**: con Local no hay endpoint en worker2 |
| P6 | Acceso directo a Pods web | desde k8s-master: `curl http://<IP_pod>` y `curl http://<ClusterIP>:8080` | **Timeout** |
| P7 | Conectividad VLAN | desde admin: `ping 10.1.100.21`, `ping <IP_VLAN_web>` | Responden |
| P8 | SSH con clave desde admin | desde admin: `ssh root@<IP_VLAN_web>`, `ssh root@10.1.100.21`, `ssh root@10.1.100.22` | Entra sin contraseña |
| P9 | Administrar la BD desde admin y desde un web | `mysql -h 10.1.100.21 -u cnvr -pcnvr2627 cnvr -e 'SELECT * FROM accesos'` | Muestra la tabla (si la imagen no trae cliente mysql: `nc -zv 10.1.100.21 3306`) |
| P10 | Servidor de logs | desde admin: `logger -n 10.1.100.22 -P 514 -d "prueba"`; en logs: `tail /var/log/remoto/*.log` | Aparece el mensaje |
| P11 | NetworkPolicy no afecta a la VLAN | P7-P9 con el deny-all aplicado | Siguen funcionando (net1 no pasa por Calico) |
| P12 | Escalado | `terraform apply -var="num_replicas=5"` | 5 Pods, cada uno con su página y su IP VLAN |

> Si la imagen admin o web no trae `mysql`, `ping` o `logger`, decidlo en la memoria y usad alternativas (`nc`, `bash /dev/tcp`), o instaladlos si la imagen tiene `apt`.

---

## 9. Problemas típicos y cómo resolverlos

| Síntoma | Causa probable | Solución |
|---|---|---|
| `terraform plan`: "no matches for kind NetworkAttachmentDefinition" | Multus no instalado | Instalarlo como en la P1.3 |
| Pod web en `ContainerCreating` y en `describe` aparece un error de whereabouts | Whereabouts no instalado | `02-vlan-workers.sh` lo instala; `kubectl -n kube-system get ds whereabouts` |
| Error macvlan "Link not found" | No existe `eth2.100` en ese worker o el nombre de la interfaz es otro | Revisar `vlan_parent_if` y volver a lanzar el script 02 |
| No hay ping admin ↔ LXC | VLAN ID distinto en workers y en VNX, o interfaz equivocada | Comparar los tags; `tcpdump -e -i eth2` en el worker para ver las etiquetas 802.1Q |
| SSH pide contraseña | Permisos de `/root/.ssh` o clave equivocada | `kubectl exec ... -- ls -la /root/.ssh`; usar `ssh -v` |
| `curl` al Ingress da 404 | Ruta distinta (mayúsculas en `G`) o falta `rewrite-target` | `kubectl describe ingress web-ingress` |
| `curl` al Ingress da 504 o timeout tras las NetworkPolicy | Las etiquetas del controlador no coinciden | `kubectl get pods -n ingress-nginx --show-labels` → `ingress_controller_labels` |
| Sigue el timeout aunque las etiquetas coincidan | El controlador usa `hostNetwork: true` y sus conexiones salen con la IP del nodo, no con la del Pod | `kubectl -n ingress-nginx get pod -o wide` (si la IP del Pod es la del nodo, es hostNetwork): consultad al profesor o añadid un `ip_block` con las IPs de los nodos |
| SSH al admin bloqueado también desde el host | La IP origen no es `10.10.20.2` (NAT) o os conectáis a worker2 | Prueba P4b; usar `10.10.10.11` |
| `mysql` dice "Host not allowed" | El usuario solo admite `10.1.100.%` | Conectarse desde la VLAN, no desde eth0 |
| Cambios en el ConfigMap que no se ven en la página | El initContainer solo se ejecuta al crear el Pod | `kubectl rollout restart deployment web` |

---

## 10. Reparto de trabajo (propuesta)

| Bloque | Martín | Brayan |
|---|---|---|
| Comprobaciones iniciales del laboratorio (tabla 0.3) | ✔ | ✔ (juntos la primera sesión) |
| VLAN en workers, Multus, NAD (`02`, `multus.tf`) | ✔ | |
| Escenario VNX LXC, MariaDB, rsyslog (`vnx/`, `03`) | | ✔ |
| Secrets, ConfigMap, Deployment web (apartado 3) | ✔ | |
| Services, Ingress, admin, NetworkPolicy (apartados 4 y 5) | | ✔ |
| Pruebas cruzadas (cada uno prueba lo del otro) | ✔ | ✔ |
| Memoria: cada uno escribe sus bloques; el otro revisa | ✔ | ✔ |

Usad un repositorio git privado compartido (el `.gitignore` ya excluye las claves y el estado de Terraform).

---

## 11. Estructura sugerida de la memoria

1. **Introducción**: objetivo, IaC y por qué Terraform.
2. **Topología**: Figura 1 con vuestras IPs (k8s_LAN, user_LAN, VLAN 10.1.100.0/24, IPs de admin, BBDD y logs) y tabla de direcciones.
3. **Desarrollo**: un subapartado por apartado del enunciado:
   - 3.1 VLAN, Multus y LXC: subinterfaces, NAD, IPAM elegida y por qué, escenario VNX (exec y filetree).
   - 3.2 SSH y Secrets: dos pares de claves, errata del enunciado, initContainer de permisos.
   - 3.3 Página personalizada: opción B, Downward API, volúmenes.
   - 3.4 Services e Ingress: ClusterIP 8080→80, NodePort 2222→22→30022, rewrite-target.
   - 3.5 NetworkPolicy: las 3 políticas, AND/OR en `from`, stateful, `externalTrafficPolicy: Local`, net1 fuera de Calico.
4. **Automatización**: scripts y orden de ejecución, y `terraform plan/apply/output`.
5. **Pruebas**: P1–P12 con captura y explicación de cada una. Incluid las negativas.
6. **Problemas encontrados y soluciones**.
7. **Conclusiones**.

---

## 12. Orden de ejecución resumido

```bash
# HOST
./scripts/00-generar-claves.sh
./scripts/01-arranque-escenario.sh
./scripts/02-vlan-workers.sh
./scripts/03-arranque-lxc.sh
# VM TERRAFORM
ssh root@terraform 'bash /shared/scripts/04-terraform-deploy.sh'
# HOST
./scripts/05-pruebas.sh
# AL TERMINAR
./scripts/99-borrar.sh
```
