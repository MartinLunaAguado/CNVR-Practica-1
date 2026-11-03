# =============================================================================
# variables.tf
# -----------------------------------------------------------------------------
# Todas las variables de entrada del despliegue. Los valores concretos se dan
# en terraform.tfvars (Terraform lo carga automáticamente).
# Tener todo parametrizado aquí permite adaptar el trabajo al laboratorio
# (nombres de interfaces, imágenes, número de grupo...) sin tocar el resto.
# =============================================================================

# ---------------------------------------------------------------- Generales --
variable "grupo" {
  description = "Número del grupo de prácticas (se usa en la ruta /servers-GX)"
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
  description = "Imagen de contenedor proporcionada para los servidores web (Nginx + SSH)"
  type        = string
}

variable "web_root" {
  description = "Directorio desde el que Nginx sirve los ficheros dentro de la imagen web"
  type        = string
  default     = "/usr/share/nginx/html"
}

variable "imagen_init" {
  description = "Imagen ligera usada por los initContainers (necesita sh, sed, cp, chmod)"
  type        = string
  default     = "busybox:1.36"
}

# ------------------------------------------------- Servidor administración ---
variable "imagen_admin" {
  description = "Imagen de contenedor proporcionada para el servidor de administración (con SSH)"
  type        = string
}

variable "admin_node" {
  description = "Nodo en el que se fuerza el Pod admin (nodeSelector). Debe coincidir con la IP a la que se hace SSH"
  type        = string
  default     = "k8s-worker1"
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
  description = "Etiquetas de los Pods del Ingress Controller (consultar con: kubectl get pods -n ingress-nginx --show-labels)"
  type        = map(string)
  default = {
    "app.kubernetes.io/name"      = "ingress-nginx"
    "app.kubernetes.io/component" = "controller"
  }
}

# --------------------------------------------------------------- VLAN --------
variable "vlan_parent_if" {
  description = "Interfaz de los nodos worker conectada a la red VlanNet (comprobar con 'ip a' en los workers)"
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

# -------------------------------------------------------------- Claves SSH ---
variable "ssh_admin_private_key" {
  description = "Clave privada que usará el admin para entrar en web/BBDD/logs"
  type        = string
  default     = "keys/admin_key"
}

variable "ssh_admin_public_key" {
  description = "Clave pública del admin (se autoriza en servidores web y contenedores LXC)"
  type        = string
  default     = "keys/admin_key.pub"
}

variable "ssh_host_public_key" {
  description = "Clave pública del host (se autoriza en el Pod admin)"
  type        = string
  default     = "keys/host_key.pub"
}
