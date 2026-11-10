# =============================================================================
# variables.tf
# -----------------------------------------------------------------------------
# Variables de entrada. Los valores del grupo están en terraform.tfvars, que
# Terraform carga automáticamente. Todo lo que puede cambiar en el laboratorio
# (interfaz de la VLAN, etiquetas del Ingress Controller...) es una variable,
# así no hay que tocar el resto de ficheros.
# =============================================================================

# ---------------------------------------------------------------- Generales --
variable "grupo" {
  description = "Número del grupo de prácticas (ruta /servers-GX del Ingress)"
  type        = number
}

variable "namespace" {
  description = "Namespace de Kubernetes donde se despliega todo"
  type        = string
  default     = "default"
}

# --------------------------------------------------------- Servidores web ----
variable "num_replicas" {
  description = "Número de Pods de servidores web del Deployment"
  type        = number
  default     = 3
}

variable "imagen_web" {
  description = "Imagen proporcionada para los servidores web (Nginx + SSH)"
  type        = string
  default     = "dgsgiros/nginx-ssh:latest"
}

variable "usuario_web" {
  description = "Usuario de la imagen web con el que se entra por SSH"
  type        = string
  default     = "webuser"
}

variable "web_root" {
  description = "Directorio desde el que Nginx sirve los ficheros en la imagen web (lo muestra scripts/02-inspeccionar-imagenes.sh)"
  type        = string
  default     = "/usr/share/nginx/html"
}

variable "imagen_init" {
  description = "Imagen ligera del initContainer que genera la página (necesita sh y sed)"
  type        = string
  default     = "busybox:1.36"
}

# ------------------------------------------------- Servidor administración ---
variable "imagen_admin" {
  description = "Imagen proporcionada para el servidor de administración (con SSH)"
  type        = string
  default     = "dgsgiros/admin-ssh:latest"
}

variable "usuario_admin" {
  description = "Usuario de la imagen admin con el que se entra por SSH"
  type        = string
  default     = "adminuser"
}

variable "ssh_gid" {
  description = "GID de adminuser y webuser (el enunciado indica 1000). Se usa como fsGroup"
  type        = number
  default     = 1000
}

variable "admin_node" {
  description = "Nodo en el que se fuerza el Pod admin (nodeSelector)"
  type        = string
  default     = "k8s-worker1"
}

variable "admin_node_ip" {
  description = "IP de ese nodo en k8s_LAN; a ella se dirige el SSH desde el host"
  type        = string
  default     = "10.10.10.11"
}

variable "admin_node_port" {
  description = "Puerto nodePort fijo del Service admin (rango 30000-32767)"
  type        = number
  default     = 30022
}

variable "host_ip" {
  description = "IP del host autorizado en la red user_LAN (Figura 2 de la P1.4)"
  type        = string
  default     = "10.10.20.2"
}

# ------------------------------------------------------------ Ingress --------
variable "ingress_class" {
  description = "IngressClass del controlador instalado en el clúster"
  type        = string
  default     = "nginx"
}

variable "ingress_controller_namespace" {
  description = "Namespace del Ingress Controller"
  type        = string
  default     = "ingress-nginx"
}

variable "ingress_controller_labels" {
  description = "Etiquetas de los Pods del Ingress Controller (kubectl get pods -n ingress-nginx --show-labels)"
  type        = map(string)
  default = {
    "app.kubernetes.io/name"      = "ingress-nginx"
    "app.kubernetes.io/component" = "controller"
  }
}

# --------------------------------------------------------------- VLAN --------
variable "vlan_parent_if" {
  description = "Interfaz de los nodos worker conectada a la red VlanNet"
  type        = string
  default     = "eth2"
}

variable "vlan_id" {
  description = "Identificador de la VLAN compartida con los contenedores LXC"
  type        = number
  default     = 100
}

variable "vlan_cidr" {
  description = "Subred IP de la VLAN"
  type        = string
  default     = "10.1.100.0/24"
}

variable "vlan_web_range_start" {
  description = "Primera IP del rango que se reparte a los Pods web en la VLAN"
  type        = string
  default     = "10.1.100.100"
}

variable "vlan_web_range_end" {
  description = "Última IP del rango que se reparte a los Pods web en la VLAN"
  type        = string
  default     = "10.1.100.150"
}

variable "vlan_admin_ip" {
  description = "IP fija del Pod admin en la VLAN (con máscara)"
  type        = string
  default     = "10.1.100.10/24"
}

variable "bbdd_ip" {
  description = "IP del contenedor LXC de base de datos en la VLAN (la fija el XML de VNX)"
  type        = string
  default     = "10.1.100.21"
}

variable "logs_ip" {
  description = "IP del contenedor LXC de logs en la VLAN (la fija el XML de VNX)"
  type        = string
  default     = "10.1.100.22"
}

# -------------------------------------------------------------- Claves SSH ---
# Par I  (administración -> servidores web y LXC)
variable "clave_admin_web_privada" {
  description = "Par I, clave PRIVADA: se entrega al Pod admin"
  type        = string
  default     = "keys/admin_web_rsa"
}

variable "clave_admin_web_publica" {
  description = "Par I, clave PÚBLICA: se autoriza en los servidores web (y en los LXC)"
  type        = string
  default     = "keys/admin_web_rsa.pub"
}

# Par II (exterior -> administración). La privada NO sale del host.
variable "clave_host_admin_publica" {
  description = "Par II, clave PÚBLICA: se autoriza en el Pod admin"
  type        = string
  default     = "keys/host_admin_rsa.pub"
}

# ---------------------------------------------------- Mantenimiento ----------
variable "permitir_salida_temporal" {
  description = "true = crea una NetworkPolicy temporal que permite la salida (Egress) de los Pods, p.ej. para instalar paquetes con apt. Dejar en false"
  type        = bool
  default     = false
}
