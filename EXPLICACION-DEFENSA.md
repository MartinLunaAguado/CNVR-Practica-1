# El proyecto explicado desde cero · Trabajo final CNVR 26-27 · Grupo 9

Este documento es para **entender** el proyecto, no para ejecutarlo (para eso está
`cnvr-trabajo-final/GUIA-LABORATORIO.md`). Está escrito suponiendo que no sabes nada:
empieza por los conceptos básicos, luego monta el escenario pieza a pieza, después recorre
cada fichero y cada comando, y termina con las preguntas que te puede hacer el profesor.

Cómo estudiarlo:

1. Lee las partes 1 a 3 seguidas: son la base. Sin ellas lo demás no se entiende.
2. Las partes 4 a 7 explican el código. Tenlas al lado de los ficheros reales.
3. La parte 8 (el camino de cada paquete) es la que más ayuda en la defensa: si sabes
   dibujar esos recorridos, sabes el trabajo.
4. La parte 11 son preguntas con respuesta. Intenta contestarlas tú antes de leer la
   respuesta.

---

## Índice

1. [La idea en dos minutos](#1-la-idea-en-dos-minutos)
2. [Conceptos básicos desde cero](#2-conceptos-básicos-desde-cero)
3. [El escenario: máquinas, redes y direcciones](#3-el-escenario-máquinas-redes-y-direcciones)
4. [Terraform y cada fichero `.tf`](#4-terraform-y-cada-fichero-tf)
5. [Los contenedores LXC con VNX](#5-los-contenedores-lxc-con-vnx)
6. [Los scripts, uno a uno](#6-los-scripts-uno-a-uno)
7. [Diccionario de comandos](#7-diccionario-de-comandos)
8. [El camino de cada paquete](#8-el-camino-de-cada-paquete)
9. [Las pruebas P1 a P13](#9-las-pruebas-p1-a-p13)
10. [Decisiones de diseño y problemas reales](#10-decisiones-de-diseño-y-problemas-reales)
11. [Preguntas de defensa con respuesta](#11-preguntas-de-defensa-con-respuesta)
12. [Limitaciones y mejoras](#12-limitaciones-y-mejoras)
13. [Chuleta de una página](#13-chuleta-de-una-página)

---

## 1. La idea en dos minutos

**Qué se pide:** desplegar, de forma **automática** y **repetible**, una pequeña aplicación
sobre un clúster de Kubernetes:

- **3 servidores web** (Nginx) que muestran una página con el nombre del Pod que la sirve,
  para que se vea que la carga se reparte entre ellos.
- **1 servidor de administración** ("admin") al que solo se puede entrar por SSH desde el
  host, y desde el cual se administra todo lo demás.
- **2 contenedores LXC fuera de Kubernetes**: una base de datos (`bbdd`) y un servidor de
  logs (`logs`).
- Todos ellos conectados además a una **red privada común** (una VLAN), por la que el admin
  entra por SSH a los web y a los LXC.
- **Seguridad de red**: por defecto todo prohibido; solo se permite lo imprescindible.

**Cómo lo hemos hecho:**

| Pieza | Herramienta | Dónde está |
|---|---|---|
| Recursos de Kubernetes (Pods, Services, Ingress, políticas, Secrets…) | **Terraform** | `shared/*.tf` |
| Contenedores LXC (bbdd y logs) | **VNX** | `vnx/cnvr-lxc-vlan.xml` |
| Preparar la red, arrancar todo en orden y probarlo | **Scripts bash** | `scripts/*.sh` |

La frase clave para la defensa: **"Infraestructura como código"**. Nada se crea a mano: todo
está descrito en ficheros. Si se borra todo (`terraform destroy`), con un solo comando
(`desplegar-todo.sh --sin-k8s`) vuelve a quedar exactamente igual. Eso es la prueba P13.

---

## 2. Conceptos básicos desde cero

### 2.1 Contenedor e imagen

Un **contenedor** es un programa que se ejecuta aislado del resto del sistema: tiene su
propio sistema de ficheros, sus propios procesos y su propia red, pero comparte el núcleo
(kernel) de Linux con la máquina donde corre. Es mucho más ligero que una máquina virtual,
porque no arranca un sistema operativo entero.

Una **imagen** es la "plantilla" de la que nace un contenedor: un paquete con los ficheros
del programa y todo lo que necesita. En el trabajo usamos dos imágenes que da el profesor,
publicadas en Docker Hub:

| Imagen | Contiene | Usuario |
|---|---|---|
| `dgsgiros/nginx-ssh:latest` | Servidor web Nginx + servidor SSH | `webuser` (GID 1000, con sudo) |
| `dgsgiros/admin-ssh:latest` | Servidor SSH + herramientas (ping, nmap, ssh…) | `adminuser` (GID 1000, con sudo) |

Y una tercera, pequeñita, para un trabajo auxiliar: `busybox:1.36` (trae `sh`, `sed`,
`wget`, `nc`…).

### 2.2 Kubernetes

**Kubernetes** (k8s) es un **orquestador de contenedores**: tú le dices "quiero 3 copias de
este servidor web" y él se encarga de arrancarlas, repartirlas entre máquinas, vigilarlas y
volver a crearlas si alguna muere.

Vocabulario imprescindible:

| Término | Qué es |
|---|---|
| **Clúster** | El conjunto de máquinas que gestiona Kubernetes. El nuestro: `k8s-master`, `k8s-worker1`, `k8s-worker2` |
| **Nodo** | Cada máquina del clúster |
| **Master** (plano de control) | El "cerebro": guarda el estado deseado y decide dónde va cada cosa. Aquí no corren nuestras aplicaciones |
| **Worker** | Los nodos donde se ejecutan los contenedores |
| **Pod** | La unidad mínima de Kubernetes: uno o varios contenedores que comparten red (misma IP) y pueden compartir volúmenes. Nuestros Pods web tienen un contenedor principal y un initContainer |
| **Deployment** | Un objeto que dice "quiero N Pods iguales a esta plantilla". Si borras un Pod, el Deployment crea otro. Sirve para escalar (cambiar N) |
| **Service** | Una dirección **estable** delante de un grupo de Pods. Los Pods cambian de IP cada vez que se recrean; el Service no |
| **Ingress** | Una regla HTTP del tipo "lo que llegue a `/servers-G9`, mándalo al Service `web-svc`" |
| **Ingress Controller** | El programa que lee esas reglas y las aplica. En el laboratorio es un Nginx que corre dentro del clúster, en el namespace `ingress-nginx` |
| **Namespace** | Una "carpeta" lógica para agrupar recursos. Nosotros lo desplegamos todo en `default` |
| **Etiqueta (label)** | Una pareja clave=valor pegada a un objeto, p. ej. `app=web`. Los Services, Deployments y políticas eligen Pods por etiqueta (**selector**) |
| **Anotación (annotation)** | Como una etiqueta, pero para información extra que leen otros programas (Multus lee la anotación `k8s.v1.cni.cncf.io/networks`) |
| **Secret** | Objeto para guardar datos sensibles (nuestras claves SSH) |
| **ConfigMap** | Objeto para guardar configuración no sensible (nuestra plantilla HTML y el `~/.ssh/config` del admin) |
| **Volumen** | Un directorio que se monta dentro del contenedor. Puede venir de un Secret, de un ConfigMap o ser una carpeta vacía (`emptyDir`) |
| **NetworkPolicy** | Reglas de cortafuegos entre Pods |
| **kubectl** | El programa de línea de comandos para hablar con el clúster (`kubectl get pods`…). Lo usamos desde el host |
| **kubelet** | El agente que corre en cada nodo y arranca los contenedores |
| **kube-proxy** | El componente de cada nodo que hace funcionar los Services (traduce la IP del Service a la IP de un Pod) |

### 2.3 La red de Kubernetes: CNI, Calico y Multus

Cada Pod necesita una interfaz de red con IP. Quien la crea es un **plugin CNI** (Container
Network Interface). Kubernetes no trae red propia: delega en el plugin.

- **Calico** es el CNI principal de nuestro clúster. Le da a cada Pod su interfaz **`eth0`**
  con una IP de la red de Pods, enruta el tráfico entre nodos y, muy importante, **es quien
  aplica las NetworkPolicy**.
- **Multus** es un "meta-plugin": se pone delante de Calico y permite que un Pod tenga
  **más de una interfaz**. Primero llama a Calico (que crea `eth0`) y después, si el Pod lo
  pide con una anotación, crea interfaces adicionales (`net1`, `net2`…).
- Cada red adicional se describe con un objeto **NetworkAttachmentDefinition** (NAD).
  Es un tipo de objeto que **no viene de serie** en Kubernetes: lo añade Multus mediante
  una **CRD** (Custom Resource Definition, "definición de recurso personalizado").

Resultado en nuestros Pods:

```
                 ┌──────────────── Pod web ────────────────┐
  red de Pods ───┤ eth0  (Calico, IP 192.168.x.x)           │  ← pasa por las NetworkPolicy
  (Calico)       │                                          │
  VLAN 1000   ───┤ net1  (Multus + macvlan, IP 10.1.100.1xx)│  ← NO pasa por Calico
                 └──────────────────────────────────────────┘
```

Esta doble interfaz es **la idea central del trabajo**: por `eth0` va el tráfico "normal"
del clúster (Ingress → web), que está filtrado; por `net1` va el tráfico de
administración por la VLAN (admin → web, admin → bbdd, admin → logs), que Calico no ve.

### 2.4 IPAM: quién reparte las IP de la VLAN

Cuando Multus crea `net1`, alguien tiene que darle una IP. Eso es el **IPAM** (IP Address
Management). Usamos dos:

- **Whereabouts** (para los Pods web): reparte IP de un rango (`10.1.100.100` a
  `10.1.100.150`) **sin repetir en todo el clúster**. Guarda qué IP ha dado en objetos de
  Kubernetes (otra CRD), así todos los nodos saben qué está ocupado. La alternativa,
  `host-local`, lleva la cuenta **por nodo**: dos Pods en nodos distintos podrían recibir la
  misma IP. Por eso no vale.
- **static** (para el admin): IP fija `10.1.100.10`. Tiene sentido porque solo hay un Pod
  admin, y así siempre sabemos dónde está.

### 2.5 macvlan

**macvlan** es el tipo de interfaz que crea Multus para `net1`. Es una interfaz "hija"
colgada de una interfaz física del nodo (la "madre", en nuestro caso `e2.1000`), con **su
propia dirección MAC**. Para la red es como si el Pod estuviera enchufado directamente al
mismo cable que el nodo. Usamos el modo `bridge`, que permite que las hijas de una misma
madre se hablen entre sí.

### 2.6 VLAN y 802.1Q

Una **VLAN** (red de área local virtual) permite tener varias redes separadas sobre el mismo
cable o switch. Cada trama Ethernet lleva una **etiqueta 802.1Q** (4 bytes) con un número de
VLAN (de 1 a 4094). Un equipo solo "ve" las tramas de su VLAN.

- En los workers creamos una **subinterfaz VLAN**: `e2.1000`. Todo lo que sale por ella sale
  por `e2` con la etiqueta 1000; lo que llega por `e2` con etiqueta 1000 entra por `e2.1000`
  (ya sin etiqueta).
- **VlanNet** es un switch virtual (**Open vSwitch**, OVS) del escenario al que están
  conectados los workers (por su interfaz `e2`) y al que VNX conecta los LXC.
  - El puerto de cada worker lleva tramas **etiquetadas** (puerto *trunk*).
  - El puerto de cada LXC es de **acceso** a la VLAN 1000: OVS pone la etiqueta al entrar
    y la quita al salir. El LXC no sabe que hay VLAN; ve tramas normales.
- Por qué 1000 y `e2`: son los valores **reales del laboratorio** (los vimos en el XML de la
  práctica 1.3, `k8s_lab-vms-vlan.xml`). La primera guía suponía `eth2` y 100, y falló.

### 2.7 SSH con claves

**SSH** permite abrir una terminal en otra máquina de forma cifrada. Se puede entrar con
contraseña o con **claves**:

- Un **par de claves** son dos ficheros: la **privada** (secreta, se queda con quien se
  conecta) y la **pública** (se puede repartir).
- En la máquina destino, la clave pública se pone en `~/.ssh/authorized_keys`. Quien tenga la
  privada correspondiente puede entrar sin contraseña.
- `sshd` es el servidor SSH (el que recibe conexiones). `ssh` es el cliente.
- `sshd` es muy exigente con los permisos: si el fichero `authorized_keys` o sus carpetas
  pueden ser modificados por otros usuarios, lo ignora (opción `StrictModes`).

El enunciado pide **dos pares independientes**:

| Par | Para qué | Privada | Pública |
|---|---|---|---|
| **Par I** `admin_web_rsa` | Admin → servidores web y LXC | En el Pod admin (Secret) | En los web (Secret) y en los LXC (VNX) |
| **Par II** `host_admin_rsa` | Host → admin | **Solo en el host** | En el Pod admin (Secret) |

Así, si alguien roba la clave del admin (Par I), no puede entrar al admin desde fuera: para
eso necesita la del Par II, que nunca sale del host.

### 2.8 Terraform

**Terraform** es una herramienta de infraestructura como código. En ficheros `.tf` describes
**cómo quieres que esté** el sistema (estado deseado), y Terraform:

1. Mira cómo está realmente.
2. Calcula la diferencia (el **plan**).
3. Crea, modifica o borra lo necesario (**apply**).

Es **declarativo**: no dices "crea esto y luego esto", dices "quiero esto". Terraform deduce
el orden mirando qué recurso usa a cuál (**dependencias implícitas**).

Para hablar con Kubernetes usa un **proveedor** (provider): el `hashicorp/kubernetes`
versión `2.23.0`. Cada tipo de objeto de Kubernetes tiene su recurso en Terraform:
`kubernetes_secret_v1`, `kubernetes_deployment_v1`, etc.

Terraform guarda lo que ha creado en un fichero **`terraform.tfstate`** (el estado). Así sabe
qué es suyo y qué tiene que borrar con `destroy`.

En el laboratorio Terraform no se ejecuta en el host, sino en una máquina aparte llamada
**`terraform`** (10.10.10.13). Esa máquina ve la carpeta del host
`/mnt/tmp/k8s_lab-calico-v02/shared` como **`/shared`**. Por eso copiamos el proyecto ahí.

### 2.9 VNX y LXC

- **VNX** es la herramienta de la asignatura para crear escenarios de red virtuales a partir
  de un fichero XML: máquinas, redes y comandos a ejecutar en ellas.
- **LXC** son contenedores de Linux "de sistema": a diferencia de los de Kubernetes, se
  parecen a una máquina completa (tienen `systemd`, servicios, se instala software con
  `apt-get`…). Por eso son cómodos para una base de datos y un servidor de logs.
- El propio clúster de Kubernetes del laboratorio está creado con VNX (por eso aparecen
  comandos como `sudo vnx -f k8s_lab-calico.xml -x config_metallb`).

### 2.10 MetalLB

Un Service de tipo **LoadBalancer** pide una IP "externa" para que se pueda acceder desde
fuera del clúster. En la nube la da el proveedor; en un laboratorio la da **MetalLB**.

- MetalLB tiene un **IPAddressPool** (`default-pool`, de `10.10.10.20` a `10.10.10.30`) del
  que asigna IP externas.
- En modo **L2** (`L2Advertisement`), uno de los nodos responde a las peticiones ARP de esa IP:
  dice "esa IP soy yo". Así el tráfico a la EXTERNAL-IP llega a ese nodo, y kube-proxy lo
  pasa al Pod.
- En el laboratorio, el **Service del Ingress Controller** (`ingress-nginx-controller`) es
  LoadBalancer. Si MetalLB no funciona, su EXTERNAL-IP se queda en `<pending>`.
- Eso es lo que pasaba en vuestra primera prueba: MetalLB descargaba sus imágenes de
  `quay.io`, que estaba inaccesible desde la universidad, así que entrasteis por el
  **NodePort** (30097), que todo Service LoadBalancer tiene además. El profesor regeneró el
  escenario el 20/11; ahora debe haber EXTERNAL-IP.

### 2.11 Base de datos y servidor de logs

- **MariaDB** es un sistema de base de datos compatible con MySQL. Escucha en el puerto
  **3306/TCP**. Se le habla con el cliente `mysql` o `mariadb`.
- **rsyslog** es el servidor de logs de Linux. Puede recibir mensajes de otras máquinas por
  el puerto **514** (UDP y TCP), el protocolo **syslog**. El comando `logger` envía mensajes.

---

## 3. El escenario: máquinas, redes y direcciones

### 3.1 El dibujo

```
                       user_LAN 10.10.20.0/24
   ┌──────────┐            │
   │   HOST   │ 10.10.20.2 │
   │ (tú)     ├────────────┤
   └──────────┘            │ 10.10.20.1
                       ┌───┴───┐
                       │  r1   │  router
                       └───┬───┘
                           │            k8s_LAN 10.10.10.0/24
   ────────┬───────────────┼───────────────┬──────────────────┬───────────
           │10.10.10.10    │10.10.10.11    │10.10.10.12       │10.10.10.13
     ┌─────┴─────┐   ┌─────┴──────┐   ┌────┴───────┐    ┌─────┴─────┐
     │k8s-master │   │k8s-worker1 │   │k8s-worker2 │    │ terraform │
     └───────────┘   │ Pod admin  │   │            │    │ (/shared) │
                     │ Pods web   │   │ Pods web   │    └───────────┘
                     │ e2.1000    │   │ e2.1000    │
                     └─────┬──────┘   └─────┬──────┘
                           │ e2 (trunk)     │ e2 (trunk)
                       ════╧════════════════╧══════════  VlanNet (Open vSwitch)
                           │ acceso VLAN 1000 │
                     ┌─────┴─────┐      ┌─────┴─────┐
                     │ LXC bbdd  │      │ LXC logs  │
                     │10.1.100.21│      │10.1.100.22│
                     └───────────┘      └───────────┘

   VLAN 1000 (10.1.100.0/24): admin 10.1.100.10 · web 10.1.100.100-150 · bbdd .21 · logs .22
   EXTERNAL-IP del Ingress (MetalLB): 10.10.10.20-30
```

### 3.2 Tablas de referencia

| Red | Para qué |
|---|---|
| `user_LAN` 10.10.20.0/24 | Donde está el host (tú) |
| `k8s_LAN` 10.10.10.0/24 | Donde están los nodos del clúster y la máquina terraform |
| Red de Pods (Calico) | La `eth0` de cada Pod. Interna del clúster |
| VLAN 1000 · 10.1.100.0/24 | La `net1` de los Pods y la interfaz de los LXC. Red de administración |

| Servicio | Puertos |
|---|---|
| `web-svc` (ClusterIP) | 8080 del Service → 80 de los Pods |
| `admin-svc` (NodePort) | 2222 del Service → 22 del Pod; desde fuera, **30022** de worker1 |
| Ingress | `http://<EXTERNAL-IP>/servers-G9` |
| MariaDB | 3306/TCP en bbdd |
| rsyslog | 514 UDP y TCP en logs |

### 3.3 Estructura del proyecto

```
cnvr-trabajo-final/
├── README.md, GUIA-LABORATORIO.md
├── shared/                 ← proyecto Terraform (se copia a /shared de la máquina terraform)
│   ├── k8s-provider.tf     proveedor de Kubernetes
│   ├── variables.tf        declaración de variables
│   ├── terraform.tfvars    valores del grupo 9
│   ├── locals.tf           valores calculados (etiquetas, ruta, nombre de la subinterfaz)
│   ├── secrets.tf          3 Secrets con las claves
│   ├── multus.tf           2 NetworkAttachmentDefinition
│   ├── configmap.tf        plantilla HTML y ~/.ssh/config del admin
│   ├── html/index.html.tpl la plantilla
│   ├── web-deployment.tf   Deployment de los 3 web
│   ├── admin-pod.tf        Pod admin
│   ├── services.tf         Service ClusterIP (web) y NodePort (admin)
│   ├── ingress.tf          Ingress /servers-G9
│   ├── network-policies.tf 3 políticas + 1 temporal
│   ├── outputs.tf          información útil tras el apply
│   └── keys/               aquí genera las claves el script 00 (no van a git)
├── vnx/
│   ├── cnvr-lxc-vlan.xml   escenario VNX con bbdd y logs
│   └── conf/ ssh/ bbdd/ logs/   ficheros que se copian dentro de los LXC
└── scripts/                00 a 07, 99, desplegar-todo.sh y config.sh
```

---

## 4. Terraform y cada fichero `.tf`

Terraform lee **todos** los `.tf` de la carpeta como si fueran uno solo. Repartirlos en
varios ficheros es solo por orden. El orden de creación no lo marca el nombre del fichero,
sino las referencias entre recursos.

### 4.0 Sintaxis mínima (HCL)

```hcl
resource "TIPO" "NOMBRE_INTERNO" {
  atributo = valor
  bloque {
    otro = valor
  }
}
```

- `TIPO` es el tipo de objeto (`kubernetes_service_v1`). `NOMBRE_INTERNO` es como lo llama
  Terraform (`web`). El nombre en Kubernetes es otro: el `metadata.name` (`web-svc`).
- Para usar un dato de otro recurso: `TIPO.NOMBRE.atributo`, por ejemplo
  `kubernetes_service_v1.web.metadata[0].name`. Esa referencia **crea una dependencia**:
  Terraform creará antes el Service.
- `var.x` es una variable; `local.x` es un valor local calculado.
- `"${...}"` mete un valor dentro de un texto: `"/servers-G${var.grupo}"` → `/servers-G9`.

### 4.1 `k8s-provider.tf`: con quién habla Terraform

```hcl
terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "2.23.0" }
  }
}
provider "kubernetes" {
  config_path = "~/.kube/config"
  ignore_annotations = [
    "cni\\.projectcalico\\.org\\/.*",
    "k8s\\.v1\\.cni\\.cncf\\.io\\/network-status",
    "k8s\\.v1\\.cni\\.cncf\\.io\\/networks-status",
  ]
}
```

- `required_providers`: qué proveedor descargar (`terraform init` lo baja). Fijamos la
  versión para que el resultado sea siempre el mismo.
- `config_path`: el fichero con la dirección del clúster y las credenciales. Lo deja
  preparado `./bin/set-terraform-kubeconf` (lo lanza el script 01).
- `ignore_annotations`: Calico y Multus **escriben anotaciones** en los Pods al arrancarlos
  (la IP que han dado, el estado de las redes). Terraform no las puso, así que pensaría que
  alguien ha cambiado el Pod "por fuera" y querría quitarlas en cada `apply`. Al ignorarlas,
  un segundo `terraform plan` dice **"No changes"** (es una de las comprobaciones de P13).
  Las expresiones son **regex**: `\\.` es un punto literal y `.*` es "cualquier cosa".

### 4.2 `variables.tf`, `terraform.tfvars` y `locals.tf`: nada escrito a fuego

- **`variables.tf`** declara cada variable: nombre, tipo, descripción y valor por defecto.
  Ejemplo:

  ```hcl
  variable "num_replicas" {
    description = "Número de Pods de servidores web del Deployment"
    type        = number
    default     = 3
  }
  ```

- **`terraform.tfvars`** da los valores del grupo (Terraform lo carga solo): `grupo = 9`,
  `vlan_parent_if = "e2"`, `vlan_id = 1000`, `host_ip = "10.10.20.2"`…
- Desde la línea de comandos se puede sobrescribir una variable: `terraform apply
  -var=num_replicas=5` (así hacemos el escalado).
- **`locals.tf`** calcula valores a partir de las variables, para no repetirlos:

  ```hcl
  locals {
    web_labels   = { app = "web" }
    admin_labels = { app = "admin" }
    ruta_ingress = "/servers-G${var.grupo}"            # /servers-G9
    vlan_if      = "${var.vlan_parent_if}.${var.vlan_id}"  # e2.1000
    ssh_dir_web   = "/home/${var.usuario_web}/.ssh"
    ssh_dir_admin = "/home/${var.usuario_admin}/.ssh"
  }
  ```

  Por qué importa: la etiqueta `app=web` aparece en el Deployment, en el Service y en la
  NetworkPolicy. Si se escribiera a mano en cada sitio y una tuviera una errata, el Service
  no encontraría los Pods. Con `local.web_labels` es imposible que se desincronicen.

**Ventaja para la defensa:** todo lo que depende del laboratorio (interfaz, VLAN, IP del
host…) es una variable. Cuando descubrimos que era `e2` y no `eth2`, solo cambiamos una
línea de `terraform.tfvars`.

### 4.3 `secrets.tf`: las claves SSH en Kubernetes

```hcl
resource "kubernetes_secret_v1" "ssh_admin_privada" {
  metadata { name = "ssh-admin-private-key", namespace = var.namespace }
  type = "Opaque"
  data = {
    "id_rsa" = file("${path.module}/${var.clave_admin_web_privada}")
  }
}
```

- `file(...)` lee el fichero `keys/admin_web_rsa` **en el momento del apply** y mete su
  contenido en el Secret. Es el equivalente a `kubectl create secret generic
  ssh-admin-private-key --from-file=id_rsa=keys/admin_web_rsa`, pero desde Terraform, como
  exige el enunciado.
- `path.module` es la carpeta de los `.tf` (`/shared`).
- `type = "Opaque"`: Secret genérico (clave → valor).
- En `data` se escribe el texto tal cual; **el proveedor lo codifica en base64**.

Hay tres Secrets:

| Secret | Clave dentro | Contenido | Quién lo usa |
|---|---|---|---|
| `ssh-admin-private-key` | `id_rsa` | Privada del Par I | Pod admin |
| `ssh-admin-authorized-keys` | `authorized_keys` | Pública del Par II | Pod admin |
| `ssh-web-authorized-keys` | `authorized_keys` | Pública del Par I | Los 3 Pods web (uno compartido) |

El enunciado pide un Secret por cada clave del admin y uno único para todos los web. Es
exactamente esto.

**Muy importante:** un Secret **no está cifrado**, solo codificado en base64 (cualquiera con
permiso de leer Secrets lo descodifica con `base64 -d`). Además, el contenido queda **en
claro en `terraform.tfstate`**. Por eso el estado y las claves están en `.gitignore`.

### 4.4 `multus.tf`: las redes de la VLAN

```hcl
resource "kubernetes_manifest" "nad_vlan_web" {
  manifest = {
    apiVersion = "k8s.cni.cncf.io/v1"
    kind       = "NetworkAttachmentDefinition"
    metadata   = { name = "vlan-web", namespace = var.namespace }
    spec = {
      config = jsonencode({
        cniVersion = "0.3.1"
        name       = "vlan-web"
        type       = "macvlan"
        master     = local.vlan_if          # "e2.1000"
        mode       = "bridge"
        ipam = {
          type        = "whereabouts"
          range       = var.vlan_cidr               # 10.1.100.0/24
          range_start = var.vlan_web_range_start    # 10.1.100.100
          range_end   = var.vlan_web_range_end      # 10.1.100.150
        }
      })
    }
  }
}
```

- **Por qué `kubernetes_manifest`**: la NAD es un tipo añadido por Multus (CRD). El proveedor
  no tiene un recurso específico como `kubernetes_secret_v1` para él, así que se usa
  `kubernetes_manifest`, que acepta **cualquier objeto** de Kubernetes escrito en HCL.
- Consecuencia: `kubernetes_manifest` consulta el clúster **ya en el plan** para saber cómo
  es ese tipo. Si Multus no estuviera instalado, fallaría en el plan ("no matches for kind").
- `spec.config` es un **texto en formato JSON** (así lo exige Multus). `jsonencode()`
  convierte el objeto HCL en ese texto.
- Lo que dice la configuración: "crea una interfaz **macvlan**, hija de **`e2.1000`**, en
  modo bridge, y pide la IP a **Whereabouts** dentro de ese rango".

La segunda NAD, `vlan-admin`, es igual salvo el IPAM:

```hcl
ipam = { type = "static", addresses = [{ address = var.vlan_admin_ip }] }   # 10.1.100.10/24
```

### 4.5 `configmap.tf` y `html/index.html.tpl`: la página y el cliente SSH

**Plantilla HTML:**

```hcl
resource "kubernetes_config_map_v1" "plantilla_web" {
  metadata { name = "plantilla-web" ... }
  data = {
    "index.html" = templatefile("${path.module}/html/index.html.tpl", { grupo = var.grupo })
  }
}
```

- `templatefile()` lee la plantilla y sustituye `${grupo}` por 9 **cuando se ejecuta
  Terraform**.
- La plantilla tiene además `__POD_NAME__`, `__NODE_NAME__` y `__POD_IP__`. Eso **no es
  sintaxis de Terraform** (no lleva `${}`), así que llega intacto al ConfigMap. Lo sustituye
  después, dentro de cada Pod, el initContainer (siguiente apartado).
- En la plantilla, el nombre del Pod va en `<p class="pod">__POD_NAME__</p>`. Por eso las
  pruebas buscan `class="pod"`.

**Configuración del cliente SSH del admin** (`ssh-config-admin`): es el fichero
`~/.ssh/config` del admin. No es secreto, por eso va en un ConfigMap y no en un Secret.

```
Host bbdd
  HostName 10.1.100.21
Host logs
  HostName 10.1.100.22
Host bbdd logs 10.1.100.21 10.1.100.22
  User root
Host *
  User webuser
  IdentityFile /home/adminuser/.ssh/id_rsa
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
```

- Gracias a esto, dentro del admin basta escribir `ssh bbdd` (en vez de `ssh
  root@10.1.100.21`) y `ssh 10.1.100.105` entra como `webuser`.
- En `ssh_config` **gana el primer valor que coincide**. Por eso `Host *` (que coincide con
  todo) va al final: si estuviera arriba, `ssh bbdd` usaría `User webuser`.
- `StrictHostKeyChecking no` y `UserKnownHostsFile /dev/null`: no se guardan las "huellas"
  de los servidores. Los Pods son **efímeros**: si un Pod se recrea y le toca una IP que
  antes tenía otro, la huella cambia y ssh bloquearía la conexión con el aviso "REMOTE HOST
  IDENTIFICATION HAS CHANGED". En un entorno de laboratorio con Pods que nacen y mueren, es
  razonable no guardarlas (en producción sería una debilidad: lo mencionamos en mejoras).

### 4.6 `web-deployment.tf`: los 3 servidores web

Es el fichero más rico. Vamos por partes.

**Cabecera y número de réplicas:**

```hcl
resource "kubernetes_deployment_v1" "web" {
  metadata { name = "web", labels = local.web_labels }
  spec {
    replicas = var.num_replicas        # 3 (5 al escalar)
    selector { match_labels = local.web_labels }
    template {
      metadata {
        labels = local.web_labels
        annotations = {
          "k8s.v1.cni.cncf.io/networks" = kubernetes_manifest.nad_vlan_web.manifest.metadata.name
          "cnvr.upm/plantilla-sha256"   = sha256(kubernetes_config_map_v1.plantilla_web.data["index.html"])
        }
      }
      ...
```

- `selector`: el Deployment controla los Pods con `app=web`. La `template` es la plantilla
  de cada Pod, y lleva esa misma etiqueta.
- Anotación **`k8s.v1.cni.cncf.io/networks = "vlan-web"`**: es lo que lee Multus para añadir
  `net1`. Como el valor se toma de la NAD (`kubernetes_manifest.nad_vlan_web...`),
  Terraform sabe que tiene que crear la NAD antes.
- Anotación **`cnvr.upm/plantilla-sha256`**: una "huella" de la plantilla. El initContainer
  solo se ejecuta al arrancar el Pod; si cambiáramos el HTML, los Pods en marcha seguirían
  con la página vieja. Al cambiar la plantilla cambia la huella, la plantilla del Pod cambia
  y el Deployment **recrea los Pods** automáticamente.

**`security_context { fs_group = 1000 }`:** todos los ficheros de los volúmenes del Pod
pasan a pertenecer al **grupo 1000**, que es el de `webuser`. Clave para las claves SSH
(ver 4.6.3).

#### 4.6.1 El initContainer `genera-index` (opción B del enunciado)

Un **initContainer** se ejecuta **antes** que el contenedor principal y **termina**. Solo
cuando acaba bien arranca Nginx.

```hcl
init_container {
  name    = "genera-index"
  image   = "busybox:1.36"
  command = ["sh", "-c"]
  args = [<<-EOT
    sed -e "s/__POD_NAME__/$POD_NAME/g" \
        -e "s/__NODE_NAME__/$NODE_NAME/g" \
        -e "s/__POD_IP__/$POD_IP/g" \
        /plantilla/index.html > /html/index.html
    chmod 644 /html/index.html
    echo "index.html generado para $POD_NAME"
  EOT
  ]
  env { name = "POD_NAME"  value_from { field_ref { field_path = "metadata.name" } } }
  env { name = "NODE_NAME" value_from { field_ref { field_path = "spec.nodeName" } } }
  env { name = "POD_IP"    value_from { field_ref { field_path = "status.podIP" } } }
  volume_mount { name = "plantilla", mount_path = "/plantilla", read_only = true }
  volume_mount { name = "html",      mount_path = "/html" }
}
```

- **Downward API** (`value_from { field_ref ... }`): Kubernetes le pasa al contenedor datos
  **de su propio Pod** como variables de entorno: su nombre, el nodo donde está y su IP.
- `sed -e "s/A/B/g"` sustituye el texto A por B en todo el fichero. Lee la plantilla del
  volumen `plantilla` (el ConfigMap, **solo lectura**) y escribe el resultado en el volumen
  `html`.
- `<<-EOT ... EOT` es un "heredoc": un texto de varias líneas.
- El `echo` final deja constancia en los logs: `kubectl logs <pod> -c genera-index`.

**Por qué opción B (initContainer) y no un sidecar:** el nombre del Pod no cambia durante
su vida, así que basta generar la página **una vez**. Un sidecar es un contenedor que corre
todo el tiempo al lado del principal: seguiría consumiendo recursos sin hacer nada útil.

#### 4.6.2 El contenedor `web`

```hcl
container {
  name  = "web"
  image = var.imagen_web                       # dgsgiros/nginx-ssh:latest
  port { name = "http", container_port = 80 }
  port { name = "ssh",  container_port = 22 }
  readiness_probe {
    http_get { path = "/", port = 80 }
    initial_delay_seconds = 2
    period_seconds        = 5
  }
  volume_mount { name = "html", mount_path = var.web_root }   # /usr/share/nginx/html
  volume_mount {
    name       = "ssh-authorized-keys"
    mount_path = "/home/webuser/.ssh/authorized_keys"
    sub_path   = "authorized_keys"
    read_only  = true
  }
}
```

- `readiness_probe`: Kubernetes hace cada 5 s un `GET /` al puerto 80. Hasta que Nginx
  responde, el Pod no está **Ready** y el Service **no le manda tráfico**. Evita enviar
  peticiones a un Pod que aún arranca.
- El volumen `html` (el `emptyDir` que rellenó el initContainer) se monta en la carpeta
  desde la que Nginx sirve ficheros (`web_root`). Así Nginx sirve la página generada.
- **`emptyDir`** es una carpeta vacía que nace con el Pod y muere con él. Sirve para que dos
  contenedores del mismo Pod compartan ficheros.

#### 4.6.3 Volúmenes y permisos de la clave (la parte "fina")

```hcl
volume { name = "plantilla" config_map { name = "plantilla-web" } }
volume { name = "html"      empty_dir {} }
volume {
  name = "ssh-authorized-keys"
  secret {
    secret_name  = "ssh-web-authorized-keys"
    default_mode = "0440"
    items { key = "authorized_keys", path = "authorized_keys", mode = "0440" }
  }
}
```

Lo que hay que entender, paso a paso:

1. Un Secret montado como volumen aparece **como ficheros**: cada clave del Secret es un
   fichero.
2. Esos ficheros pertenecen a **root**. Con `fs_group = 1000`, además tienen el **grupo
   1000**.
3. Modo **0440** = `r--r-----`: el dueño (root) puede leer, el grupo (1000) puede leer, los
   demás nada. Nadie puede escribir.
4. `webuser` pertenece al grupo 1000 → **puede leer** su `authorized_keys`. Nadie puede
   modificarlo → **`sshd` lo acepta** (StrictModes exige que no lo puedan modificar otros).
5. **`sub_path`**: se monta **solo el fichero** `authorized_keys` dentro de `~/.ssh`, no el
   volumen entero. Si montáramos el volumen sobre `~/.ssh`, Kubernetes pondría ahí una
   carpeta con permisos especiales (con escritura para otros y enlaces simbólicos) y `sshd`
   rechazaría la clave por permisos.

Los permisos en octal, por si te lo preguntan: cada cifra es una suma de r=4, w=2, x=1, para
dueño, grupo y otros. `0440` = r (4) para dueño, r (4) para grupo, nada (0) para otros.
`0644` = rw-r--r--.

### 4.7 `admin-pod.tf`: el servidor de administración

Es un **Pod suelto** (no un Deployment): solo hay uno y tiene una IP fija en la VLAN.

```hcl
resource "kubernetes_pod_v1" "admin" {
  metadata {
    name   = "admin"
    labels = local.admin_labels                       # app=admin
    annotations = { "k8s.v1.cni.cncf.io/networks" = "vlan-admin" }
  }
  spec {
    node_selector = { "kubernetes.io/hostname" = var.admin_node }   # k8s-worker1
    security_context { fs_group = var.ssh_gid }                      # 1000
    container {
      name  = "admin"
      image = var.imagen_admin
      port { name = "ssh", container_port = 22 }
      volume_mount { name = "ssh-private-key",     mount_path = "/home/adminuser/.ssh/id_rsa",          sub_path = "id_rsa" ... }
      volume_mount { name = "ssh-authorized-keys", mount_path = "/home/adminuser/.ssh/authorized_keys", sub_path = "authorized_keys" ... }
      volume_mount { name = "ssh-config",          mount_path = "/home/adminuser/.ssh/config",          sub_path = "config" ... }
    }
    volume { ... secret ssh-admin-private-key,     modo 0440 }
    volume { ... secret ssh-admin-authorized-keys, modo 0440 }
    volume { ... config_map ssh-config-admin,      modo 0444 }
  }
}
```

- **`node_selector`**: obliga a que el Pod vaya **siempre a `k8s-worker1`**. Cada nodo tiene
  la etiqueta `kubernetes.io/hostname=<su nombre>`. Por qué: junto con
  `externalTrafficPolicy: Local` (siguiente apartado), así sabemos a qué IP de nodo
  tenemos que conectarnos (10.10.10.11) y se conserva la IP del host.
- Tres ficheros en `~/.ssh`, cada uno de un recurso distinto:

| Fichero | Origen | Contenido | Para qué |
|---|---|---|---|
| `id_rsa` | Secret `ssh-admin-private-key` | Privada del Par I | Entrar en web y LXC |
| `authorized_keys` | Secret `ssh-admin-authorized-keys` | Pública del Par II | Que el host entre aquí |
| `config` | ConfigMap `ssh-config-admin` | Config del cliente SSH | `ssh bbdd`, usuarios… |

**El detalle de la clave privada con 0440:** el cliente `ssh` se niega a usar una clave
privada si otros pueden leerla ("UNPROTECTED PRIVATE KEY FILE"), **pero esa comprobación
solo la hace si el fichero es del propio usuario**. Aquí el fichero es de **root** y
`adminuser` lo lee por el grupo 1000, así que `ssh` lo acepta. Por la misma razón, si
entras con `kubectl exec` (que entra como **root**), el fichero sí es "tuyo", tiene permisos
de grupo y `ssh` lo rechaza. Por eso hay que entrar al admin **como adminuser, por SSH**.

### 4.8 `services.tf`: direcciones estables

**Service web (ClusterIP):**

```hcl
resource "kubernetes_service_v1" "web" {
  metadata { name = "web-svc" }
  spec {
    type     = "ClusterIP"
    selector = local.web_labels          # app=web
    port { name = "http", protocol = "TCP", port = 8080, target_port = 80 }
  }
}
```

- **ClusterIP**: una IP virtual interna del clúster. Solo se puede usar desde dentro.
- `port = 8080` es el puerto **del Service**; `target_port = 80` es el puerto **del Pod**.
  Quien llama a `web-svc:8080` acaba en el puerto 80 de uno de los Pods.
- `selector`: el Service reparte entre los Pods con `app=web` que estén Ready. Esa lista se
  ve con `kubectl get endpoints web-svc`.
- Quien hace la traducción IP-del-Service → IP-de-un-Pod es **kube-proxy**, con reglas
  iptables en cada nodo.

**Service admin (NodePort):**

```hcl
resource "kubernetes_service_v1" "admin" {
  metadata { name = "admin-svc" }
  spec {
    type                    = "NodePort"
    selector                = local.admin_labels
    external_traffic_policy = "Local"
    port { name = "ssh", protocol = "TCP", port = 2222, target_port = 22, node_port = 30022 }
  }
}
```

- **NodePort**: además de la ClusterIP, abre un puerto (rango 30000-32767) en **los nodos**,
  accesible desde fuera. Tres puertos distintos:
  - `node_port = 30022`: el que usas desde fuera (`ssh -p 30022 ... @10.10.10.11`).
  - `port = 2222`: el del Service dentro del clúster.
  - `target_port = 22`: el del Pod (donde escucha sshd).
- **`externalTrafficPolicy: Local`**, la decisión más importante del trabajo:
  - Con el valor por defecto (`Cluster`), un nodo que recibe la conexión puede mandarla a un
    Pod de **otro** nodo; para que la respuesta vuelva por el mismo camino, kube-proxy
    **cambia la IP de origen por la del nodo (SNAT)**. El Pod vería la conexión como si
    viniera de 10.10.10.x, no del host.
  - Con `Local`, el nodo solo entrega la conexión a Pods **que estén en él mismo** y **no
    cambia la IP de origen**. El Pod admin ve **10.10.20.2**, y la NetworkPolicy que solo
    permite al host funciona.
  - Efecto secundario: en los nodos donde no hay Pod admin (worker2), el puerto 30022 no
    responde. Por eso fijamos el admin en worker1 con `node_selector` y nos conectamos a la
    IP de worker1. Y eso mismo se comprueba en P5 (worker2:30022 debe fallar).

### 4.9 `ingress.tf`: la puerta HTTP

```hcl
resource "kubernetes_ingress_v1" "web" {
  metadata {
    name        = "web-ingress"
    annotations = { "nginx.ingress.kubernetes.io/rewrite-target" = "/" }
  }
  spec {
    ingress_class_name = var.ingress_class        # nginx
    rule {
      http {
        path {
          path      = local.ruta_ingress            # /servers-G9
          path_type = "Prefix"
          backend { service { name = "web-svc", port { number = 8080 } } }
        }
      }
    }
  }
}
```

- La regla: lo que llegue con ruta que **empiece** por `/servers-G9` (`Prefix`) se envía al
  Service `web-svc`, puerto 8080.
- `ingress_class_name = "nginx"`: qué Ingress Controller debe aplicar la regla (en un
  clúster podría haber varios).
- **`rewrite-target: /`**: el Ingress Controller cambia la ruta `/servers-G9` por `/` antes
  de reenviar la petición. Sin esto, el Nginx del Pod buscaría un fichero llamado
  `servers-G9` dentro de su carpeta y devolvería **404**.
- Cualquier otra ruta (por ejemplo `/otra-ruta`) no coincide con ninguna regla y el Ingress
  Controller responde 404. Eso se comprueba en P3.
- Detalle importante para las políticas: el Ingress Controller, aunque la regla nombre al
  Service, **se conecta directamente a las IP de los Pods** (lee la lista de endpoints). Por
  eso la NetworkPolicy de los web permite el puerto **80** (el del Pod) y como origen los
  Pods del Ingress Controller.

### 4.10 `network-policies.tf`: el cortafuegos

Reglas básicas de las NetworkPolicy (hay que sabérselas):

1. **Sin políticas, todo está permitido.**
2. Cuando una política **selecciona** un Pod para un sentido (Ingress = entrada, Egress =
   salida), en ese sentido **solo pasa lo que permitan las reglas**.
3. Son **aditivas**: lo permitido es la **unión** de todas las políticas que seleccionan el
   Pod. No hay reglas de "denegar": se deniega todo por defecto y se van sumando permisos.
4. Son **stateful**: si se permite iniciar una conexión, las respuestas vuelven solas, sin
   necesitar otra regla.
5. Los puertos son los **del Pod** (80, 22), no los del Service (8080, 2222), porque la
   política se aplica cuando el paquete ya va al Pod.
6. Las aplica **Calico** sobre la interfaz `eth0`. **No afectan a `net1`** (la VLAN), porque
   ese tráfico sale por la macvlan directamente a `e2.1000` sin pasar por Calico.

**Política 1: `default-deny-all`**

```hcl
spec {
  pod_selector {}                       # vacío = TODOS los Pods del namespace
  policy_types = ["Ingress", "Egress"]  # sin reglas -> nada permitido
}
```

Bloquea todo lo que entra y todo lo que sale de todos los Pods de `default`. A partir de
aquí, solo se abre lo necesario.

**Política 2: `web-allow-from-ingress-nginx`**

```hcl
spec {
  pod_selector { match_labels = { app = "web" } }
  policy_types = ["Ingress"]
  ingress {
    from {
      namespace_selector { match_labels = { "kubernetes.io/metadata.name" = "ingress-nginx" } }
      pod_selector       { match_labels = { "app.kubernetes.io/name" = "ingress-nginx",
                                            "app.kubernetes.io/component" = "controller" } }
    }
    ports { protocol = "TCP", port = "80" }
  }
}
```

- Selecciona los Pods web y permite **entrada al puerto 80** solo desde los Pods del
  Ingress Controller.
- `namespace_selector` y `pod_selector` **dentro del mismo bloque `from`** = **Y lógico**:
  Pods con esas etiquetas **y** que estén en el namespace `ingress-nginx`. Si fueran dos
  bloques `from` separados sería un **O**: bastaría con estar en ese namespace (cualquier
  Pod) o tener esas etiquetas (en cualquier namespace). Pregunta típica.
- `kubernetes.io/metadata.name` es una etiqueta que Kubernetes pone **automáticamente** a
  cada namespace con su nombre.
- Requisito oculto: el Pod del Ingress Controller tiene que tener una **IP de Pod** (no la
  del nodo). Si usara la red del nodo (`hostNetwork`), su tráfico llegaría con la IP del
  nodo, no coincidiría con el `pod_selector`, y el Ingress daría 504. Por eso lo comprueba
  el script 02.

**Política 3: `admin-allow-ssh-from-host`**

```hcl
spec {
  pod_selector { match_labels = { app = "admin" } }
  policy_types = ["Ingress"]
  ingress {
    from  { ip_block { cidr = "10.10.20.2/32" } }
    ports { protocol = "TCP", port = "22" }
  }
}
```

- Solo se puede entrar al admin por el **puerto 22** y desde la **IP del host** (`/32` =
  exactamente esa IP).
- Funciona **gracias a `externalTrafficPolicy: Local`**: sin ella, el origen sería la IP de
  un nodo y no coincidiría.

**Política 4 (temporal, opcional): `temporal-allow-egress`**

```hcl
resource "kubernetes_network_policy_v1" "salida_temporal" {
  count = var.permitir_salida_temporal ? 1 : 0
  ...
  spec { pod_selector {}  policy_types = ["Egress"]  egress {} }
}
```

- `count = condición ? 1 : 0`: el recurso existe **solo** si se aplica con
  `-var=permitir_salida_temporal=true`. Si no, Terraform lo borra.
- `egress {}` (una regla vacía) = permitir **toda** la salida.
- La usa el script 07 para que los Pods puedan descargar el cliente SQL con `apt`, y luego
  la quita. **Demuestra que las políticas son aditivas**: no se toca `default-deny-all`, se
  **suma** un permiso y luego se retira.

**Qué queda permitido al final** (por `eth0`):

| Origen → destino | ¿Permitido? | Por qué |
|---|---|---|
| Ingress Controller → web:80 | Sí | Política 2 |
| Host (10.10.20.2) → admin:22 | Sí | Política 3 + `Local` |
| Máquina terraform → admin:22 | No | No es la IP del host |
| Pod de otro namespace → web | No | Solo se permite al Ingress Controller |
| web → web | No | default-deny (salida y entrada) |
| web → Internet | No | default-deny (salida) |
| Admin → web / bbdd / logs **por la VLAN** | Sí | Va por `net1`: Calico no lo ve |

### 4.11 `outputs.tf`: información al terminar

- `data "kubernetes_resources" "web_pods"`: una **fuente de datos** (`data`), es decir, algo
  que Terraform **lee** pero no crea. Lee la lista de Pods con `app=web`.
- `web_pods_ip_vlan`: para cada Pod, saca la IP de `net1` de la anotación
  `k8s.v1.cni.cncf.io/network-status` que escribe Multus (`jsondecode` la convierte de texto
  JSON a objeto). Si aún no está, pone `"pendiente"`.
- Por qué hace falta `terraform apply -refresh-only` después: Terraform lee los Pods justo
  después de crearlos, cuando Multus quizá no ha escrito todavía la anotación. El
  `-refresh-only` vuelve a leer el estado real sin cambiar nada. Lo mismo tras escalar a 5 y
  volver a 3: sin refresco, el output seguiría mostrando 5 Pods.
- `ssh_admin`: el comando exacto para entrar al admin.

---

## 5. Los contenedores LXC con VNX

### 5.1 El XML `vnx/cnvr-lxc-vlan.xml`, bloque a bloque

**Cabecera:**

```xml
<global>
  <scenario_name>cnvr_tf_lxc_vlan</scenario_name>
  <automac offset="50"/>
  <vm_mgmt type="none"/>
  ...
</global>
```

- `scenario_name`: el nombre del escenario (VNX lo usa para crearlo y destruirlo).
- `automac offset="50"`: VNX genera las MAC automáticamente; el desplazamiento evita que
  coincidan con las del escenario de Kubernetes.
- `vm_mgmt type="none"`: no crea red de gestión adicional.

**Redes:**

```xml
<net name="VlanNet" mode="openvswitch" managed="no"/>
<net name="virbr0"  mode="virtual_bridge" managed="no"/>
```

- `VlanNet` es el switch OVS **que ya creó el escenario de Kubernetes**. `managed="no"` le
  dice a VNX: "usa esta red, pero no la crees ni la borres". Sin esto, VNX intentaría
  gestionarla y podría romper la red de los workers. Fue uno de los fallos de la primera
  versión.
- `virbr0` es el puente de libvirt con NAT y DHCP: da salida a Internet. Solo lo usamos para
  que `apt-get` pueda instalar paquetes.

**Cada máquina (bbdd como ejemplo):**

```xml
<vm name="bbdd" type="lxc" arch="x86_64">
  <filesystem type="cow">/usr/share/vnx/filesystems/vnx_rootfs_lxc_ubuntu64-20.04-v025-vnxlab</filesystem>
  <if id="1" net="VlanNet">
    <vlan><tag id="1000"/></vlan>
    <ipv4>10.1.100.21/24</ipv4>
  </if>
  <if id="9" net="virbr0">
    <ipv4>dhcp</ipv4>
  </if>
```

- `filesystem type="cow"`: el sistema de ficheros base del contenedor. **cow** (*copy on
  write*): todos los contenedores comparten la imagen base y cada uno guarda solo sus
  cambios. La ruta es la del laboratorio (Ubuntu 20.04, v025).
- `<if id="1" net="VlanNet">` con `<tag id="1000"/>`: interfaz conectada a VlanNet como
  **puerto de acceso de la VLAN 1000**. IP fija 10.1.100.21.
- `<if id="9" net="virbr0">` con DHCP: la salida a Internet.

**filetree: copiar ficheros del host al contenedor:**

```xml
<filetree seq="configurar" root="/root/conf/">conf/ssh</filetree>
<filetree seq="configurar" root="/root/conf/">conf/bbdd</filetree>
```

- Copia la **carpeta entera** `vnx/conf/ssh` a `/root/conf/` → queda
  `/root/conf/ssh/authorized_keys`. Igual con `conf/bbdd` → `/root/conf/bbdd/...`.
- `seq="configurar"`: se ejecuta al lanzar la secuencia `configurar`
  (`vnx -f ... -x configurar`).
- Error de la primera versión: los comandos buscaban `/root/conf/authorized_keys` (sin la
  subcarpeta) y fallaban con `cp: cannot stat`.

**exec: comandos dentro del contenedor (se ejecutan en orden):**

1. **Instalar paquetes:**

   ```bash
   for i in $(seq 1 30); do getent hosts archive.ubuntu.com >/dev/null && break; sleep 2; done;
   export DEBIAN_FRONTEND=noninteractive LC_ALL=C;
   apt-get update;
   if dpkg -l mysql-server-8.0 2>/dev/null | grep -q '^ii'; then
     apt-get purge -y mysql-server mysql-server-8.0 ...; apt-get autoremove -y;
     rm -rf /var/lib/mysql /etc/mysql/mysql.conf.d;
   fi;
   apt-get install -y mariadb-server mariadb-client openssh-server
   ```

   - El bucle `for` espera hasta 60 s a que el contenedor **pueda resolver nombres**
     (`getent hosts` pregunta al DNS). Al arrancar, el DHCP de `virbr0` tarda un poco; sin
     esta espera `apt-get` fallaba en `logs` (problema real del laboratorio).
   - `DEBIAN_FRONTEND=noninteractive`: que `apt` no haga preguntas (no hay nadie para
     contestar). `LC_ALL=C`: idioma neutro, evita avisos de "locale".
   - La imagen traía **MySQL 8.0**, que choca con MariaDB. Si está instalado (`dpkg -l` y
     una línea que empiece por `ii` = instalado), se purga junto con sus datos
     (`/var/lib/mysql`). Si no se borran los datos, MariaDB no arranca ("found previous
     version"). Se hace **solo si está instalado** para que la secuencia se pueda repetir
     sin errores.
   - En XML, `&&` se escribe `&amp;&amp;` y `<` se escribe `&lt;`, porque `&` y `<` son
     caracteres especiales del XML.

2. **SSH solo con clave:**

   ```bash
   mkdir -p /root/.ssh;
   cp /root/conf/ssh/authorized_keys /root/.ssh/authorized_keys;
   chmod 700 /root/.ssh; chmod 600 /root/.ssh/authorized_keys;
   sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config;
   sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config;
   systemctl enable ssh; systemctl restart ssh
   ```

   - Pone la **pública del Par I** en el `authorized_keys` de root: el admin entra como
     root.
   - `700` y `600`: solo root puede leer y escribir (lo que exige sshd).
   - `PermitRootLogin prohibit-password`: root puede entrar, pero **solo con clave**.
     `PasswordAuthentication no`: nadie puede entrar con contraseña.
   - `sed -i 's/^#\?X.*/Y/'`: busca la línea que empieza por X (comentada con `#` o no) y la
     sustituye por Y, en el propio fichero (`-i`).
   - `systemctl enable` (arrancar siempre al iniciar) y `restart` (aplicar ya).

3. **MariaDB** (en bbdd):

   ```bash
   cp /root/conf/bbdd/60-cnvr.cnf /etc/mysql/mariadb.conf.d/60-cnvr.cnf;
   systemctl enable mariadb; systemctl restart mariadb;
   mysql < /root/conf/bbdd/init.sql
   ```

4. **rsyslog** (en logs):

   ```bash
   cp /root/conf/logs/10-remoto.conf /etc/rsyslog.d/10-remoto.conf;
   mkdir -p /var/log/remoto;
   chown syslog:adm /var/log/remoto;
   systemctl enable rsyslog; systemctl restart rsyslog
   ```

   - En Ubuntu, rsyslog arranca como root pero **luego pasa a funcionar como el usuario
     `syslog`**. Si la carpeta es de root, no puede crear ficheros en ella ("Permission
     denied"). Por eso `chown syslog:adm`. Problema real del laboratorio.

### 5.2 Los ficheros de configuración

**`conf/bbdd/60-cnvr.cnf`:**

```ini
[mysqld]
bind-address = 0.0.0.0
port         = 3306
```

Por defecto MariaDB solo escucha en `127.0.0.1` (solo conexiones desde la propia máquina).
`0.0.0.0` = escuchar en **todas las interfaces**, así se puede conectar desde la VLAN.

**`conf/bbdd/init.sql`:**

```sql
CREATE DATABASE IF NOT EXISTS cnvr;
CREATE USER IF NOT EXISTS 'cnvr'@'10.1.100.%' IDENTIFIED BY 'cnvr2627';
GRANT ALL PRIVILEGES ON cnvr.* TO 'cnvr'@'10.1.100.%';
FLUSH PRIVILEGES;
USE cnvr;
CREATE TABLE IF NOT EXISTS accesos (id INT AUTO_INCREMENT PRIMARY KEY, origen VARCHAR(64) NOT NULL,
                                    mensaje VARCHAR(255), fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
INSERT INTO accesos (origen, mensaje) VALUES ('bbdd', 'Base de datos inicializada por VNX');
```

- `'cnvr'@'10.1.100.%'`: en MySQL/MariaDB un usuario es **usuario + desde dónde**. `%` es
  comodín: el usuario `cnvr` solo puede conectarse **desde la VLAN**. Desde otra red daría
  "Host is not allowed".
- `IF NOT EXISTS`: se puede ejecutar varias veces sin error (repetible).
- La tabla `accesos` la usan las pruebas: cada inserción guarda `USER()`, que devuelve
  `usuario@IP_del_cliente`. Así queda registrado **desde qué máquina** se conectó cada uno.

**`conf/logs/10-remoto.conf`:**

```
module(load="imudp")   input(type="imudp" port="514")
module(load="imtcp")   input(type="imtcp" port="514")
template(name="PorOrigen" type="string" string="/var/log/remoto/%HOSTNAME%.log")
if $fromhost-ip != '127.0.0.1' then {
  action(type="omfile" dynaFile="PorOrigen")
  stop
}
```

- Carga los módulos de entrada UDP y TCP y escucha en el **514**.
- `template` con `dynaFile`: el nombre del fichero depende del mensaje; cada máquina origen
  va a su propio fichero (`/var/log/remoto/admin.log`, etc.).
- `if $fromhost-ip != '127.0.0.1'`: solo los mensajes que vienen de **fuera**. `stop` evita
  que además se escriban en el syslog normal.

**`conf/ssh/authorized_keys`:** lo crea el script 00 copiando `admin_web_rsa.pub` (pública
del Par I).

### 5.3 Base de datos: por qué MariaDB y no MySQL

El profesor dijo después (19/11) que valía cualquier sistema de base de datos instalable
como paquete y que MySQL daba menos problemas. Nosotros ya teníamos MariaDB funcionando
(quitando el MySQL 8.0 de la imagen) y pasando todas las pruebas, así que la mantuvimos.
Es una decisión razonable: cambiar algo que ya está probado introduce riesgo sin ganar nada.

---

## 6. Los scripts, uno a uno

Antes, unas nociones de bash que aparecen en todos:

| Construcción | Significado |
|---|---|
| `#!/bin/bash` | Primera línea: este fichero se ejecuta con bash |
| `set -e` | Si un comando falla, el script se para (no sigue con algo roto) |
| `source config.sh` | Carga las variables de `config.sh` en el script actual |
| `VAR=valor` / `$VAR` | Definir y usar una variable (sin espacios alrededor del `=`) |
| `$(comando)` | Ejecuta el comando y pone ahí su salida: `POD=$(kubectl ...)` |
| `cmd1 \| cmd2` | Tubería: la salida de cmd1 es la entrada de cmd2 |
| `cmd1 && cmd2` | cmd2 solo si cmd1 funcionó |
| `cmd1 \|\| cmd2` | cmd2 solo si cmd1 falló. `\|\| true` = "si falla, da igual" |
| `>/dev/null 2>&1` | Tira la salida normal y la de errores (silencio) |
| `for x in a b; do ...; done` | Bucle |
| `f(){ ...; }` | Definir una función |
| `[ -f fichero ]` | ¿Existe el fichero? |
| `"$1"`, `"$@"`, `$*` | Primer argumento, todos los argumentos |

### 6.1 `config.sh`: los parámetros comunes

No se ejecuta solo: lo cargan todos los demás con `source`. Define rutas
(`K8S_DIR=/mnt/tmp/k8s_lab-calico-v02`), nombres (`WORKERS="k8s-worker1 k8s-worker2"`),
IP, `VLAN_PARENT_IF=e2`, `VLAN_ID=1000`, etc. **Debe coincidir con `terraform.tfvars`**:
uno lo leen los scripts y el otro Terraform.

Tiene una función, `sync_shared`, que copia `shared/` a la carpeta compartida
(`$K8S_DIR/shared`) y el script 05 a `/shared/scripts/`.

`REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"` calcula sola la carpeta del
proyecto, para que los scripts funcionen estén donde estén.

### 6.2 `00-generar-claves.sh`

```bash
ssh-keygen -q -t rsa -b 4096 -N "" -C "${k}@cnvr-g${GRUPO}" -f "$k"
chmod 600 admin_web_rsa host_admin_rsa
chmod 644 admin_web_rsa.pub host_admin_rsa.pub
cp admin_web_rsa.pub "$REPO/vnx/conf/ssh/authorized_keys"
```

- `ssh-keygen`: crea un par de claves. `-t rsa -b 4096` (RSA de 4096 bits), `-N ""` (sin
  frase de paso, para que todo sea automático), `-C` (comentario), `-f` (nombre del
  fichero), `-q` (silencioso).
- Si ya existen, no las regenera (si lo hiciera, las que hay desplegadas dejarían de valer).
- Copia la pública del Par I a donde VNX la recoge para los LXC.

### 6.3 `01-arranque-escenario.sh`

```bash
/lab/cnvr/bin/get-k8s-calico                       # descarga el escenario Kubernetes con Calico
cd /mnt/tmp/k8s_lab-calico-v02 && ./bin/start-k8s-calico   # lo arranca
sudo vnx -f k8s_lab-terraform.xml --create          # crea la máquina terraform
sudo vnx -f k8s_lab-terraform.xml -x install-terraform     # instala Terraform en ella
./bin/get-master-kubeconf                           # credenciales del clúster en el host (para kubectl)
./bin/set-terraform-kubeconf                        # y en la máquina terraform (para Terraform)
# comprobación de MetalLB y, si hace falta: sudo vnx -f k8s_lab-calico.xml -x config_metallb
sync_shared                                         # copia shared/ a /shared
```

- `vnx -f FICHERO --create`: crea el escenario descrito en el XML.
- `vnx -f FICHERO -x SECUENCIA`: ejecuta una secuencia de comandos definida en el XML
  (`install-terraform`, `config_metallb`…).
- La comprobación de MetalLB (añadida tras el correo del 20/11) mira que existan
  `default-pool` y `default-l2-advertisement`; si no, lanza `config_metallb` hasta 3 veces,
  esperando 20 s antes para que arranquen los Pods de MetalLB.

### 6.4 `02-inspeccionar-imagenes.sh`

No cambia nada; solo **mira**. Arranca un Pod temporal con cada imagen en un namespace
aparte (`inspeccion`) y comprueba lo que el proyecto da por hecho:

- `id webuser`: ¿GID 1000? (lo usamos como `fsGroup`).
- Permisos del home y de `.ssh`.
- `sshd_config` (que no desactive las claves).
- Puertos a la escucha: 22 en las dos, 80 en la web.
- `nginx -T | grep root`: desde qué carpeta sirve Nginx (→ `web_root`).
- Herramientas disponibles (ping, nmap, curl, mysql…).

Y datos del clúster: interfaces de worker1 (cuál es la de VlanNet), Multus/Whereabouts,
etiquetas e IP del Ingress Controller, cómo se publica, y los **puntos de control** (VLAN y
filesystem del XML de la práctica 1.3, que exista `e2`, EXTERNAL-IP, IP del host).

Comandos clave: `kubectl run` (crear un Pod rápido), `kubectl wait --for=condition=Ready`
(esperar a que esté listo), `kubectl exec POD -- comando` (ejecutar dentro).

### 6.5 `03-vlan-workers.sh`

En cada worker, por SSH:

```bash
modprobe 8021q                                            # carga el módulo de VLAN del kernel
ip link set e2 up                                         # enciende la interfaz madre
ip link add link e2 name e2.1000 type vlan id 1000        # crea la subinterfaz VLAN (si no existe)
ip link set e2.1000 up                                    # la enciende
ip -d link show e2.1000                                   # la muestra con detalle (-d)
```

- La subinterfaz **no lleva IP**: solo es la "madre" de las macvlan de los Pods.
- **No sobrevive a un reinicio** del worker (no se guarda en ninguna configuración
  permanente): si se reinicia, hay que repetir el script.

Después comprueba que existe la CRD de Multus y, si no está **Whereabouts**, lo instala:

```bash
kubectl apply -f .../whereabouts.cni.cncf.io_ippools.yaml -f ... -f .../daemonset-install.yaml
kubectl -n kube-system rollout status ds/whereabouts --timeout=240s
```

- `kubectl apply -f`: crea o actualiza los objetos descritos en esos ficheros (las CRD y un
  DaemonSet).
- Un **DaemonSet** es como un Deployment pero con **un Pod por nodo**: Whereabouts necesita
  estar en cada nodo.
- `rollout status`: espera a que el DaemonSet esté desplegado del todo.

### 6.6 `04-arranque-lxc.sh`

```bash
corriendo(){ sudo lxc-info -n "$1" -s 2>/dev/null | grep -q RUNNING; }
if corriendo bbdd && corriendo logs; then echo "ya arrancados"
else sudo vnx -f cnvr-lxc-vlan.xml --create; sleep 20; fi
sudo vnx -f cnvr-lxc-vlan.xml -x configurar
sudo lxc-attach -n bbdd -- ip -4 -br addr
sudo lxc-attach -n bbdd -- ss -ltnu | grep -E ':(22|3306|514)[[:space:]]'
```

- `lxc-info -n NOMBRE -s`: estado de un contenedor LXC (RUNNING, STOPPED…).
- Si ya existen (por ejemplo, en P13 después de un `destroy`), no los vuelve a crear; solo
  repite `configurar`, que es **idempotente** (se puede repetir sin estropear nada).
- `lxc-attach -n NOMBRE -- comando`: ejecuta un comando dentro del contenedor (como
  `kubectl exec`, pero para LXC).

### 6.7 `05-terraform-deploy.sh` (se ejecuta **en la máquina terraform**)

```bash
cd /shared
terraform init -input=false
terraform validate
terraform plan -input=false -out=plan.tfplan
terraform apply -input=false plan.tfplan
terraform apply -refresh-only -auto-approve -input=false
terraform output
```

- `-input=false`: que no pregunte nada (modo automático).
- `plan -out=plan.tfplan` + `apply plan.tfplan`: se aplica **exactamente** el plan que se
  ha calculado (si entre medias cambiara algo, no se aplicaría otra cosa).
- El `-refresh-only` final es para que los outputs tengan las IP de la VLAN.

### 6.8 `06-pruebas.sh`

Hace las pruebas P1 a P10 y marca cada comprobación con `[OK]` o `[FALLO]`. Dos funciones
lo organizan:

```bash
debe_ir(){     if "$@" >/dev/null 2>&1; then ok "$d"; else ko "$d"; fi; }   # OK si FUNCIONA
debe_fallar(){ if "$@" >/dev/null 2>&1; then ko "...BLOQUEADO"; else ok "(bloqueado)"; fi; }  # OK si FALLA
```

`debe_fallar` es para las **pruebas negativas**: demostrar que lo que debe estar bloqueado
lo está. Son tan importantes como las positivas.

Trucos que usa:

- `ADMIN="ssh -i clave_host ... -p 30022 adminuser@10.10.10.11"`: todo lo que se hace "desde
  el admin" es `$ADMIN "comando"`.
- `timeout 6 bash -c "</dev/tcp/IP/PUERTO"`: bash tiene un fichero especial `/dev/tcp/...`
  que **abre una conexión TCP**. Si conecta, el puerto está abierto. `timeout 6` lo corta a
  los 6 s. Es una forma de probar un puerto sin instalar nada.
- Pod `tester` (busybox) en otro namespace (`pruebas-np`): sirve de "atacante" externo.
  Tiene que estar **en otro namespace** porque un Pod de `default` tiene su propia salida
  bloqueada por default-deny, y la prueba no demostraría nada del destino.
- `nc -w 6 IP 22`: abre una conexión al 22 y lee lo que dice el servidor. Un sshd responde
  con un texto que empieza por `SSH-`; si aparece, el puerto está abierto.
- `nmap -Pn -p 3306 IP`: escanea el puerto 3306. `-Pn` = no hagas ping antes, prueba
  directamente.
- `logger -n IP -P 514 -d 'mensaje'`: envía un mensaje syslog por UDP (`-d`) a ese servidor.
- La URL del Ingress se calcula sola: primero la EXTERNAL-IP; si no hay, el NodePort.
- `--skip-ssl`: el cliente SQL que hay en los Pods es moderno y **por defecto exige
  conexión cifrada (TLS)**; nuestra MariaDB 10.3 no tiene TLS configurado. Con
  `--skip-ssl` se conecta sin cifrar. Activar TLS sería una mejora.

### 6.9 `07-cliente-bd.sh`

Las imágenes no traen cliente SQL. Para la prueba completa:

1. `terraform apply -var=permitir_salida_temporal=true`: crea la política temporal que
   permite la salida.
2. En el admin y en cada web: `sudo apt-get install -y mariadb-client`.
3. `terraform apply` (sin la variable): Terraform ve que el recurso ya no debe existir y
   **borra la política**. Vuelve el bloqueo total.

Lo instalado **se pierde si el Pod se recrea** (los contenedores parten siempre de la
imagen). Por eso hay que relanzarlo tras escalar o tras un `destroy`.

### 6.10 `99-borrar.sh` y `desplegar-todo.sh`

- `99-borrar.sh`: copia de seguridad de `/shared` en tu carpeta personal (porque `/mnt/tmp`
  se borra), `terraform destroy`, destruye los LXC (`vnx --destroy`) y quita las
  subinterfaces VLAN (`ip link del e2.1000`). No toca el clúster.
- `desplegar-todo.sh`: ejecuta 00, 01 (o solo `sync_shared` con `--sin-k8s`), 03, 04 y 05
  en orden. Es el "un solo comando" de la infraestructura como código.

---

## 7. Diccionario de comandos

### 7.1 kubectl

| Comando | Qué hace |
|---|---|
| `kubectl get nodes` | Lista los nodos y su estado (Ready) |
| `kubectl get pods -o wide` | Pods con IP y nodo (`-o wide` = más columnas) |
| `kubectl get pods -l app=web` | Solo los Pods con esa etiqueta (`-l` = label selector) |
| `kubectl get pods -A` | Pods de **todos** los namespaces |
| `kubectl get pods -n ingress-nginx` | Pods de un namespace concreto |
| `kubectl get deploy,pods,svc,ingress,networkpolicy` | Varios tipos a la vez |
| `kubectl get svc web-svc` | Un Service |
| `kubectl get endpoints web-svc` | Las IP:puerto de los Pods detrás del Service |
| `kubectl get network-attachment-definitions` (o `net-attach-def`) | Las NAD de Multus |
| `kubectl get crd` | Los tipos añadidos al clúster |
| `kubectl describe pod X` | Todo sobre un objeto, con eventos (útil para errores) |
| `kubectl logs X -c contenedor` | Lo que ha escrito un contenedor (`-c` elige cuál) |
| `kubectl exec X -c web -- comando` | Ejecuta un comando dentro (entra como root) |
| `kubectl exec -it X -- sh` | Abre una terminal dentro (`-it` = interactivo) |
| `kubectl run tester --image=busybox --restart=Never --command -- sleep 3600` | Crea un Pod suelto que no se reinicia |
| `kubectl wait --for=condition=Ready pod/tester --timeout=120s` | Espera a que esté listo |
| `kubectl create namespace X` / `delete namespace X` | Crear o borrar un namespace (y todo lo de dentro) |
| `kubectl delete pod X --grace-period=0 --force` | Borrado forzado, sin esperar |
| `kubectl apply -f fichero.yaml` | Crea o actualiza objetos desde un fichero |
| `kubectl rollout status ds/whereabouts` | Espera a que termine un despliegue |
| `kubectl get secret X -o jsonpath='{.data.authorized_keys}' \| base64 -d` | Lee un dato del Secret y lo descodifica |

**`-o jsonpath='{...}'`**: saca un campo concreto del objeto. Ejemplos del proyecto:

- `{.items[0].metadata.name}`: nombre del primer elemento de la lista.
- `{.status.loadBalancer.ingress[0].ip}`: EXTERNAL-IP de un Service.
- `{.spec.ports[?(@.port==80)].nodePort}`: el nodePort del puerto que sea el 80 (`?()` es
  un filtro).
- `{.spec.externalTrafficPolicy}`: el valor de ese campo.

### 7.2 terraform

| Comando | Qué hace |
|---|---|
| `terraform init` | Prepara la carpeta: descarga el proveedor en `.terraform/` |
| `terraform fmt` | Formatea los `.tf` con el estilo estándar |
| `terraform validate` | Revisa la sintaxis y las referencias sin tocar el clúster |
| `terraform plan` | Muestra qué va a crear (+), cambiar (~) o borrar (-) |
| `terraform apply` | Muestra el plan, pide `yes` y lo aplica |
| `terraform apply -target=TIPO.NOMBRE` | Aplica solo ese recurso (y lo que necesite) |
| `terraform apply -var=num_replicas=5` | Da un valor a una variable para esta ejecución |
| `terraform apply -refresh-only -auto-approve` | Vuelve a leer el estado real sin cambiar nada |
| `terraform destroy` | Borra todo lo que creó Terraform |
| `terraform output [nombre]` | Muestra los outputs |
| `terraform state list` | Lista los recursos que gestiona |

`-auto-approve` = no preguntar `yes`. `-input=false` = no preguntar nada.

**La función `tf` del host:**

```bash
tf() { ssh -t root@terraform "cd /shared && terraform $*"; }
```

- Define una función llamada `tf`. Al escribir `tf apply -target=X`, se ejecuta
  `ssh -t root@terraform "cd /shared && terraform apply -target=X"`.
- `$*` se sustituye **en el host** por los argumentos que le pasas.
- `ssh -t` reserva una terminal, para que Terraform pueda preguntarte `yes`.
- `cd /shared &&` garantiza que Terraform se ejecute siempre en la carpeta correcta. Sin
  esto pasó lo de `No configuration files` (se ejecutaba en `/root`).

### 7.3 Red y sistema

| Comando | Qué hace |
|---|---|
| `ip -br addr` | Interfaces y sus IP, resumido (`-br` = brief) |
| `ip -4 addr show net1` | IP v4 de una interfaz concreta |
| `ip -d link show e2.1000` | Detalle de una interfaz (`-d`): aquí, `vlan protocol 802.1Q id 1000` |
| `ip link add link e2 name e2.1000 type vlan id 1000` | Crea la subinterfaz VLAN |
| `ip link set X up` / `ip link del X` | Encender / borrar una interfaz |
| `ss -ltnu` | Puertos a la escucha: `l` listening, `t` TCP, `u` UDP, `n` números (no nombres) |
| `ping -c 2 -W 2 IP` | 2 pings, esperando 2 s cada uno |
| `curl http://...` | Petición HTTP. `-s` silencioso, `-o /dev/null` tira el cuerpo, `-w '%{http_code}'` muestra el código, `-m 6` máximo 6 s |
| `wget -T 5 -qO- URL` | Petición HTTP (busybox): `-T` tiempo máximo, `-q` silencioso, `-O-` a pantalla |
| `nc -w 6 IP 22` | Abre una conexión TCP y muestra lo que llega |
| `nmap -Pn -p 3306 IP` | ¿Está abierto el 3306? |
| `tcpdump -e -n -i e2 vlan` | Ver tramas con etiqueta VLAN (diagnóstico) |
| `getent hosts nombre` | Resolver un nombre (prueba de DNS) |

### 7.4 SSH, VNX, LXC y bases de datos

| Comando | Qué hace |
|---|---|
| `ssh -i clave -p 30022 adminuser@10.10.10.11` | Entra con una clave concreta (`-i`) a un puerto (`-p`) |
| `ssh bbdd "mysql -e '...'"` | Ejecuta un comando en otra máquina y vuelve |
| `ssh-keygen` / `ssh-copy-id root@nodo` | Crear claves / copiar tu pública a otra máquina |
| `echo $SSH_CLIENT` | Dentro de una sesión SSH: IP y puerto **de quien se conectó** |
| `sudo vnx -f X.xml --create` / `--destroy` | Crear / destruir un escenario |
| `sudo vnx -f X.xml -x secuencia` | Ejecutar una secuencia del XML |
| `sudo lxc-attach -n bbdd -- comando` | Comando dentro de un LXC |
| `sudo lxc-info -n bbdd -s` | Estado de un LXC |
| `mysql --skip-ssl -h IP -u cnvr -pcnvr2627 cnvr -e "SQL"` | Conectar a la BD (`-h` servidor, `-u` usuario, `-p` contraseña pegada, último argumento la base de datos, `-e` ejecutar SQL) |
| `logger -n IP -P 514 -d "texto"` | Enviar un mensaje syslog por UDP |
| `systemctl enable/restart/status servicio` | Gestionar servicios |

### 7.5 Texto y ficheros

| Comando | Qué hace |
|---|---|
| `grep patrón fichero` | Líneas que contienen el patrón. `-c` cuenta, `-n` número de línea, `-q` silencioso (solo éxito/fallo), `-E` regex extendida, `-r` recursivo, `-o` solo la parte que coincide |
| `sed -i 's/A/B/g' fichero` | Sustituir A por B en el fichero |
| `tee fichero` | Muestra en pantalla **y** guarda en fichero (`06-pruebas.sh \| tee pruebas.txt`) |
| `sort \| uniq -c` | Ordenar y contar repeticiones (cuántas veces respondió cada Pod) |
| `base64 -d` | Descodificar base64 |
| `cp -r origen/. destino/` | Copiar el **contenido** de una carpeta |
| `chmod 600 f` / `chown usuario:grupo f` | Cambiar permisos / dueño |

---

## 8. El camino de cada paquete

Si sabes contar estos recorridos, sabes el trabajo.

### 8.1 Navegador → página web (`http://<EXTERNAL-IP>/servers-G9`)

```
Host 10.10.20.2
  │ 1. GET /servers-G9 a la EXTERNAL-IP (p. ej. 10.10.10.20)
  ▼
r1 (router)  ──►  k8s_LAN
  │ 2. MetalLB (modo L2): un nodo responde al ARP de 10.10.10.20
  ▼
Nodo que anuncia la IP
  │ 3. kube-proxy: Service LoadBalancer ingress-nginx-controller → Pod del Ingress Controller
  ▼
Pod Ingress Controller (Nginx, ns ingress-nginx)
  │ 4. Mira las reglas: /servers-G9 → web-svc:8080. Reescribe la ruta a "/" (rewrite-target)
  │ 5. Elige un Pod de los endpoints de web-svc y conecta DIRECTAMENTE a IP_Pod:80
  ▼
Calico (en la eth0 del Pod web)
  │ 6. ¿Origen = Pod con etiquetas del controller en ns ingress-nginx, puerto 80? Sí → pasa
  ▼
Pod web: Nginx sirve /usr/share/nginx/html/index.html (generado por el initContainer)
  │ 7. La respuesta vuelve por el mismo camino (las políticas son stateful)
  ▼
Navegador: "Esta página la ha servido el Pod web-xxxx"
```

Si recargas varias veces, el Ingress Controller reparte entre los 3 Pods y cambia el nombre.

Con NodePort en vez de EXTERNAL-IP (como en vuestra primera prueba), los pasos 1-3 son:
host → `10.10.10.11:30097` → kube-proxy de worker1 → Pod del Ingress Controller.

### 8.2 Host → admin por SSH

```
Host 10.10.20.2: ssh -i host_admin_rsa -p 30022 adminuser@10.10.10.11
  │ 1. Llega a worker1:30022 (NodePort)
  ▼
kube-proxy de worker1
  │ 2. externalTrafficPolicy Local: hay Pod admin en este nodo → destino IP_Pod_admin:22
  │    SIN cambiar la IP de origen (sigue siendo 10.10.20.2)
  ▼
Calico (eth0 del Pod admin)
  │ 3. ¿Origen 10.10.20.2/32 y puerto 22? Sí → pasa
  ▼
sshd del admin
  │ 4. Comprueba la clave contra /home/adminuser/.ssh/authorized_keys (pública del Par II,
  │    root:1000, 0440). La acepta. Entra como adminuser
  ▼
Dentro: echo $SSH_CLIENT → 10.10.20.2 ...
```

Desde la máquina terraform (10.10.10.13) el paso 3 falla: el origen no es el host. Contra
worker2:30022 falla el paso 2: con `Local`, worker2 no tiene Pod admin y no reenvía.

### 8.3 Admin → servidor web por la VLAN

```
Admin (adminuser): ssh 10.1.100.105
  │ 1. ~/.ssh/config: Host * → User webuser, IdentityFile id_rsa (privada Par I)
  │ 2. La IP 10.1.100.105 está en la red de net1 → sale por net1 (macvlan, 10.1.100.10)
  ▼
e2.1000 de worker1 → e2 con etiqueta 802.1Q 1000 → VlanNet (OVS)
  │ 3. Si el Pod web está en worker2, la trama cruza VlanNet hasta e2 de worker2 → e2.1000
  │    → macvlan net1 del Pod web. Si está en worker1, la macvlan en modo bridge la entrega
  │    directamente
  ▼
sshd del Pod web
  │ 4. authorized_keys (pública del Par I, root:1000, 0440) → acepta. Entra como webuser
```

**Calico no interviene en ningún momento**: el tráfico va por `net1`, no por `eth0`. Por eso
funciona aunque `default-deny-all` bloquee toda la salida del admin y toda la entrada del web.

### 8.4 Admin → bbdd y logs

```
Admin: ssh bbdd   → ~/.ssh/config: HostName 10.1.100.21, User root
  │ net1 → e2.1000 → VlanNet (trama con etiqueta 1000)
  ▼
OVS: puerto de acceso VLAN 1000 del LXC bbdd → quita la etiqueta
  ▼
LXC bbdd (10.1.100.21): sshd, authorized_keys de root = pública del Par I → entra como root

Admin: mysql --skip-ssl -h 10.1.100.21 -u cnvr ...
  │ mismo camino, puerto 3306
  ▼
MariaDB (bind-address 0.0.0.0): usuario 'cnvr'@'10.1.100.%' y el origen es 10.1.100.10 → OK

Admin: logger -n 10.1.100.22 -P 514 -d "prueba"
  │ mismo camino, UDP 514
  ▼
rsyslog (imudp) → /var/log/remoto/admin.log
```

### 8.5 Lo que se bloquea

```
tester (ns pruebas-np) ── wget http://IP_Pod_web:80 ──► Calico eth0 del web
                                                       ¿origen = Ingress Controller? NO → descartado
tester ── wget http://IP_web-svc:8080 ──► kube-proxy → IP_Pod_web:80 → Calico → descartado
web1 ── curl http://IP_web2 ──► Calico eth0 de web1: salida denegada (default-deny Egress) → descartado
web1 ── ping 8.8.8.8 ──► salida denegada → descartado
```

---

## 9. Las pruebas P1 a P13

| Prueba | Qué demuestra | Cómo | Resultado esperado |
|---|---|---|---|
| **P1** Recursos | Que todo existe | `kubectl get deploy,pods,svc,ingress,networkpolicy` | 3 web y admin Running; admin en worker1; admin-svc NodePort/Local; web-svc ClusterIP 8080→80 |
| **P2** Multus | Cada Pod tiene `net1` en la VLAN | `kubectl exec POD -c web -- ip -4 addr show net1` | 10.1.100.1xx en cada web; 10.1.100.10 en el admin |
| **P3** Página e Ingress | Página personalizada, reparto de carga y solo `/servers-G9` | `curl` repetido; `curl /otra-ruta` | 200, varios nombres de Pod, 404 en otra ruta |
| **P4** SSH host → admin | Par II y conservación de IP origen | `ssh -i host_admin_rsa -p 30022 ...` y `echo $SSH_CLIENT` | Entra sin contraseña; origen 10.10.20.2 |
| **P5** Solo el host | ipBlock y `Local` | Mismo SSH desde terraform y contra worker2 | Bloqueado en los dos |
| **P6** NetworkPolicy | default-deny y web solo desde el Ingress | tester → Pod web, tester → web-svc, tester → admin:22, web → web, web → Internet | Todo bloqueado; el Ingress sí funciona |
| **P7** VLAN | Conectividad por `net1` | Desde el admin, ping a web, bbdd y logs | Responden todos |
| **P8** SSH por la VLAN | Par I hacia web y LXC | `ssh IP_web`, `ssh bbdd`, `ssh logs` | Entra como webuser / root |
| **P9** Base de datos | Admin y web llegan a la BD | `nmap -p 3306`, `ssh bbdd mysql ...`, cliente SQL con inserción | Puerto abierto; inserciones con `USER()` = usuario@IP |
| **P10** Logs | rsyslog recibe mensajes | `logger` desde el admin y `grep` en logs | El mensaje aparece en `/var/log/remoto/` |
| **P11** VLAN y políticas | Que P7 y P8 funcionan con default-deny | Explicación | `net1` no pasa por Calico |
| **P12** Cliente SQL | Inserción y consulta reales | `07-cliente-bd.sh` + P9 | 37 correctas |
| **P13** Repetible | Infraestructura como código | `plan` sin cambios, escalado a 5, `destroy` + `desplegar-todo.sh --sin-k8s` | Todo vuelve a funcionar sin tocar nada |

Las cifras: **35 correctas** sin cliente SQL (las de P9 con cliente salen como `[info]`) y
**37** tras `07-cliente-bd.sh`.

Tres cuidados de las pruebas negativas (te pueden preguntar por qué se hacen así):

- **No desde el nodo donde está el Pod**: Calico deja pasar el tráfico del propio nodo
  hacia sus Pods (lo necesita kubelet para las sondas; de hecho las readiness probes de los
  web siguen funcionando con default-deny activo).
- **No desde un Pod de `default`**: su salida ya está bloqueada; la prueba no diría nada del
  destino. Por eso el tester está en otro namespace.
- **Antes y después**: la captura del "antes" de las políticas solo se puede hacer antes de
  aplicarlas (por eso se despliega por partes con `-target`).

---

## 10. Decisiones de diseño y problemas reales

### 10.1 Decisiones de diseño (donde se gana nota)

1. **Opción B (initContainer) frente al sidecar**: el nombre del Pod no cambia; generar la
   página una vez basta y no consume recursos después.
2. **Whereabouts para los web, IP fija para el admin**: Whereabouts no repite IP entre
   nodos (host-local sí podría); el admin es único y conviene que tenga dirección conocida.
3. **Secrets como ficheros con `sub_path`, modo 0440 y `fsGroup` 1000**: el usuario puede
   leer, nadie puede modificar, sshd acepta. Sin initContainers que copien claves.
4. **Un Secret por clave del admin y uno compartido por los web**: como pide el enunciado.
5. **Cliente SSH en un ConfigMap**: no es secreto; sin guardar huellas de Pods efímeros.
6. **`externalTrafficPolicy: Local` + `nodeSelector`**: conserva la IP del host para el
   ipBlock y fija dónde está el admin.
7. **Las políticas no afectan a la VLAN**: separación de planos: el tráfico de usuario
   (filtrado) y el de administración (por su red aparte).
8. **Todo parametrizado con variables y locals**: cambiar de laboratorio es cambiar
   `terraform.tfvars` y `config.sh`.
9. **`ignore_annotations`**: el segundo `plan` dice "No changes".
10. **Huella sha256 de la plantilla**: cambiar el HTML recrea los Pods solo.
11. **Scripts idempotentes**: se pueden repetir (claves no regeneradas, VLAN solo si no
    existe, LXC solo si no están, `IF NOT EXISTS` en SQL, purga de MySQL solo si está).

### 10.2 Problemas reales del laboratorio y su solución

| # | Problema | Solución |
|---|---|---|
| 1 | Interfaz y VLAN distintas (`e2`, 1000) | Detectado con el script 02 y el XML de la práctica 1.3 |
| 2 | `VlanNet` sin `managed="no"` y filesystem distinto | Copiar los valores del laboratorio |
| 3 | `filetree` copia carpetas enteras (`cp: cannot stat`) | Rutas `/root/conf/ssh/...` |
| 4 | La imagen LXC traía MySQL 8.0, incompatible con MariaDB | Purgarlo antes. Diagnóstico con `apt-get install -s -o Debug::pkgProblemResolver=yes mariadb-server` |
| 5 | Datos viejos en `/var/lib/mysql` (MariaDB no arrancaba) | Borrarlos, solo si MySQL estaba instalado |
| 6 | Carrera con el DHCP (apt sin red) | Esperar a que resuelva DNS |
| 7 | rsyslog sin permisos (se ejecuta como `syslog`) | `chown syslog:adm /var/log/remoto` |
| 8 | Cliente SQL exige TLS | `--skip-ssl` |
| 9 | Terraform ejecutado en `/root` | Función `tf` / `cd /shared` |
| 10 | `destroy`: `Pod admin still exists` | Esperar y repetir `destroy` (o forzar el borrado) |
| 11 | Ingress sin EXTERNAL-IP (MetalLB, quay.io inaccesible) | NodePort mientras tanto; luego `config_metallb` |
| 12 | Elección de base de datos | Se mantuvo MariaDB: funcionaba |

---

## 11. Preguntas de defensa con respuesta

Intenta responder antes de leer.

**Generales y Terraform**

1. **¿Qué es la infraestructura como código y cómo la aplicáis?**
   Describir la infraestructura en ficheros versionables en vez de crearla a mano. Todo el
   clúster está en `.tf`, los LXC en un XML y el orden en scripts. Se demuestra con P13:
   `destroy` y un solo comando lo deja igual.

2. **¿Qué diferencia hay entre `plan` y `apply`?**
   `plan` calcula y muestra los cambios sin hacerlos; `apply` los hace (tras confirmar).

3. **¿Cómo sabe Terraform en qué orden crear las cosas?**
   Por las referencias: si el Deployment usa `kubernetes_secret_v1.ssh_web_autorizadas...`,
   el Secret se crea antes. Es una dependencia implícita.

4. **¿Qué es el `terraform.tfstate` y por qué no se sube a git?**
   El registro de lo que Terraform ha creado. Contiene en claro el contenido de los Secrets
   (la clave privada del Par I).

5. **¿Por qué `kubernetes_manifest` para la NAD?**
   La NAD es un tipo añadido por Multus (CRD); el proveedor no tiene un recurso específico,
   y `kubernetes_manifest` admite cualquier objeto. Consulta el clúster en el plan, así que
   Multus tiene que estar instalado.

6. **¿Para qué sirve `-target`?**
   Aplicar solo un recurso (y sus dependencias). Lo usamos para desplegar por partes y
   capturar el antes y el después de las políticas.

7. **¿Por qué hace falta `-refresh-only`?**
   Las IP de la VLAN las escribe Multus en una anotación después de crear el Pod. El refresco
   vuelve a leer el estado real para que el output las muestre.

8. **¿Por qué un segundo `plan` dice "No changes"?**
   Porque el estado real coincide con el descrito; y las anotaciones que añaden Calico y
   Multus están en `ignore_annotations`.

**Kubernetes**

9. **¿Qué pasa si muere un Pod web?**
   El Deployment crea otro. Su initContainer genera la página con el nombre nuevo y
   Whereabouts le da una IP de la VLAN. El Service lo añade cuando está Ready.

10. **¿Cómo escaláis?**
    `terraform apply -var=num_replicas=5`. Cada Pod nuevo tiene su página y su IP en la VLAN.

11. **¿Qué hace la Downward API?**
    Pasa al contenedor datos de su propio Pod (nombre, nodo, IP) como variables de entorno.

12. **¿Qué diferencia hay entre ClusterIP, NodePort y LoadBalancer?**
    ClusterIP: IP interna, solo dentro del clúster. NodePort: además abre un puerto en los
    nodos, accesible desde fuera. LoadBalancer: además pide una IP externa (MetalLB aquí).

13. **¿Por qué el Service web usa 8080 y los Pods 80?**
    Lo pide el enunciado. `port` es el del Service y `targetPort` el del Pod; kube-proxy
    traduce.

14. **¿Qué hace `rewrite-target: /`?**
    Cambia `/servers-G9` por `/` antes de mandar la petición al Pod; si no, Nginx buscaría un
    fichero `servers-G9` y daría 404.

15. **¿Qué es la readiness probe?**
    Una comprobación periódica (GET / al 80). Hasta que responde, el Pod no recibe tráfico
    del Service.

16. **¿Qué es un initContainer y en qué se diferencia de un sidecar?**
    Se ejecuta antes del principal y termina. Un sidecar corre a la vez y todo el tiempo.

17. **¿Qué es un emptyDir?**
    Una carpeta vacía que vive lo que el Pod; sirve para compartir ficheros entre sus
    contenedores (initContainer escribe, Nginx lee).

**Secrets y SSH**

18. **¿Un Secret está cifrado?**
    No, solo codificado en base64. Quien pueda leer Secrets en el namespace lo lee.

19. **¿Por qué dos pares de claves?**
    Separar privilegios: la clave del admin (Par I) no sirve para entrar al admin desde
    fuera; para eso hace falta la del Par II, que nunca sale del host.

20. **¿Por qué la clave privada tiene modo 0440 y aun así funciona?**
    El fichero es de root; `ssh` solo exige permisos privados si el fichero es del propio
    usuario. `adminuser` la lee por el grupo 1000 que pone `fsGroup`.

21. **¿Por qué no funciona `ssh` si entro con `kubectl exec`?**
    `kubectl exec` entra como root. Entonces el fichero sí es "tuyo" y tiene permisos de
    grupo: `ssh` lo rechaza ("UNPROTECTED PRIVATE KEY FILE"). Hay que entrar como
    adminuser por SSH.

22. **¿Para qué sirve `sub_path`?**
    Montar solo el fichero dentro de `~/.ssh` sin tapar el directorio. Montando el volumen
    entero, `~/.ssh` quedaría con permisos que sshd rechaza (StrictModes).

23. **¿Y `fsGroup`?**
    Hace que los ficheros de los volúmenes tengan el grupo 1000, el de los usuarios de las
    imágenes, para que puedan leerlos con permisos de grupo.

24. **¿Por qué el `~/.ssh/config` va en un ConfigMap?**
    No es secreto. Los ConfigMap son para configuración; los Secrets para datos sensibles.

25. **¿Por qué no se guardan las huellas de los servidores (known_hosts)?**
    Los Pods son efímeros y reutilizan IP con claves de host distintas: ssh bloquearía la
    conexión. En producción sería una debilidad.

**Redes y políticas**

26. **¿Por qué el admin llega a los web por SSH si hay una denegación total?**
    Porque va por `net1` (macvlan sobre la VLAN), que no pasa por Calico. Las políticas solo
    actúan sobre `eth0`.

27. **¿Qué pasa si quitáis `externalTrafficPolicy: Local`?**
    El nodo puede cambiar la IP de origen por la suya (SNAT); el Pod ve una IP de nodo y la
    regla ipBlock del host deja de coincidir: el host no podría entrar.

28. **¿Por qué el puerto de la política web es el 80 y no el 8080?**
    La política se aplica en el Pod, cuando el Service ya ha traducido 8080 → 80. Además el
    Ingress Controller conecta directamente a los Pods.

29. **¿Qué significa poner `namespace_selector` y `pod_selector` en el mismo `from`?**
    Y lógico: Pods con esas etiquetas **y** en ese namespace. En bloques separados sería O.

30. **¿Qué significa que las políticas sean aditivas? ¿Y stateful?**
    Aditivas: lo permitido es la suma de todas las que seleccionan el Pod (por eso la
    política temporal abre la salida sin tocar default-deny). Stateful: las respuestas de
    una conexión permitida vuelven solas.

31. **¿Por qué no se puede entrar al admin desde la máquina terraform?**
    Su IP (10.10.10.13) no es la del host (10.10.20.2/32) que permite el ipBlock.

32. **¿Por qué falla contra worker2:30022?**
    Con `Local`, solo responden los nodos que tienen un Pod admin; el admin está fijado en
    worker1.

33. **¿Qué es una VLAN y cómo se conecta el Pod a ella?**
    Una red separada por etiquetas 802.1Q. En el worker, `e2.1000` etiqueta con 1000; Multus
    crea en el Pod una macvlan hija de `e2.1000`. En VlanNet (OVS), los LXC están en
    puertos de acceso de la VLAN 1000.

34. **¿Por qué Whereabouts y no host-local?**
    host-local reparte por nodo y podría dar la misma IP en dos nodos; Whereabouts lleva la
    cuenta en todo el clúster.

35. **¿Qué es Multus?**
    Un meta-plugin CNI que permite varias interfaces por Pod: llama a Calico para `eth0` y
    a otros plugins (macvlan) para las redes que pide la anotación.

36. **¿Qué hace MetalLB y qué pasó en el laboratorio?**
    Da IP externas a los Services LoadBalancer y las anuncia por ARP (modo L2). Sus imágenes
    venían de quay.io, inaccesible desde el laboratorio: el Ingress no tenía EXTERNAL-IP y
    usamos su NodePort. El profesor regeneró el escenario.

37. **¿Por qué el Pod del Ingress Controller debe tener IP de Pod?**
    La política de los web identifica al controlador por sus etiquetas. Si usara la red del
    nodo, su tráfico llegaría con la IP del nodo y no coincidiría con el `pod_selector`.

**LXC y servicios**

38. **¿Qué hace `managed="no"` en VlanNet?**
    Que VNX use la red ya creada por el escenario de Kubernetes sin crearla ni destruirla.

39. **¿Por qué `bind-address = 0.0.0.0`?**
    Por defecto MariaDB solo escucha en 127.0.0.1; así acepta conexiones desde la VLAN.

40. **¿Qué significa `'cnvr'@'10.1.100.%'`?**
    Usuario cnvr que solo puede conectarse desde direcciones de la VLAN.

41. **¿Por qué `--skip-ssl`?**
    El cliente SQL moderno exige TLS por defecto y MariaDB 10.3 no lo tiene configurado.
    Activar TLS sería una mejora.

42. **¿Por qué `chown syslog` en la carpeta de logs?**
    rsyslog deja de ser root tras arrancar y funciona como `syslog`; necesita poder escribir.

43. **¿Por qué se pierde el cliente SQL al recrear un Pod?**
    Se instaló dentro del contenedor en marcha; un Pod nuevo parte otra vez de la imagen
    original.

---

## 12. Limitaciones y mejoras

- **La clave privada del Par I queda en `terraform.tfstate`** en claro. Mejora: estado
  remoto cifrado o un gestor de secretos (Vault, Sealed Secrets).
- **Los Secrets solo están en base64**. Mejora: cifrado en reposo de etcd y RBAC estricto.
- **El cliente SQL instalado a mano se pierde** al recrear el Pod. Mejora: imagen propia
  con el cliente, o un initContainer/Job.
- **La subinterfaz VLAN no persiste** a reinicios del worker. Mejora: configurarla de forma
  permanente (netplan/systemd-networkd) o con un DaemonSet.
- **Sin TLS en MariaDB** (`--skip-ssl`). Mejora: certificados y `require_secure_transport`.
- **Sin known_hosts** en el cliente SSH del admin. Aceptable en el laboratorio.
- **Archivos montados con `sub_path` no se actualizan solos** si cambia el Secret; hay que
  recrear el Pod.
- **Un solo Pod admin** (punto único de fallo). Es lo que pide el enunciado.
- **La VLAN no tiene políticas**: cualquier equipo de la VLAN puede hablar con cualquiera.
  Se confía en que solo están nuestros equipos.

---

## 13. Chuleta de una página

```
QUÉ:   3 web (Deployment) + 1 admin (Pod) en Kubernetes con Calico, 2 LXC (bbdd, logs) con VNX,
       todos en la VLAN 1000 (10.1.100.0/24) por Multus. Todo con Terraform + scripts.

REDES: eth0 = Calico (filtrada por NetworkPolicy)   net1 = macvlan sobre e2.1000 (no filtrada)
       host 10.10.20.2 · worker1 .11 · worker2 .12 · terraform .13 · Ingress EXTERNAL-IP 10.10.10.20-30
       admin 10.1.100.10 (static) · web 10.1.100.100-150 (whereabouts) · bbdd .21 · logs .22

CLAVES: Par I admin→web/LXC (privada en admin, pública en web y LXC)
        Par II host→admin (privada SOLO en el host, pública en admin)
        Secrets montados como fichero: sub_path + 0440 + fsGroup 1000 → root:1000 r--r-----

WEB:   initContainer busybox + Downward API: sed __POD_NAME__ → emptyDir → Nginx
       web-svc ClusterIP 8080→80 · Ingress /servers-G9 → web-svc:8080, rewrite-target /

ADMIN: nodeSelector worker1 · admin-svc NodePort 2222→22, nodePort 30022, externalTrafficPolicy Local
       → sin SNAT → el Pod ve 10.10.20.2 → ipBlock 10.10.20.2/32 puerto 22

POLÍTICAS: default-deny-all (Ingress+Egress) · web: solo :80 desde Pods del controller en ns
       ingress-nginx (mismo from = Y) · admin: solo :22 desde el host · temporal-allow-egress (count)
       Aditivas, stateful, puertos del Pod, solo eth0.

LXC:   managed="no" en VlanNet · tag 1000 · filetree copia carpetas · purga MySQL 8.0 → MariaDB
       bind 0.0.0.0, usuario 'cnvr'@'10.1.100.%' · rsyslog 514 UDP/TCP, chown syslog

PRUEBAS: 35 OK (37 con 07-cliente-bd.sh) · P13 destroy + desplegar-todo.sh --sin-k8s
```
