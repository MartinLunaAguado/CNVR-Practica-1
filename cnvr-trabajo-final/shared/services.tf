# =============================================================================
# services.tf  (Apartado 4, puntos 1 y 2 del enunciado)
# =============================================================================

# Service ClusterIP para los servidores web: 8080 (Service) -> 80 (Pods).
# Solo es accesible dentro del clúster; desde fuera se llega por el Ingress.
resource "kubernetes_service_v1" "web" {
  metadata {
    name      = "web-svc"
    namespace = var.namespace
  }
  spec {
    type     = "ClusterIP"
    selector = local.web_labels
    port {
      name        = "http"
      protocol    = "TCP"
      port        = 8080
      target_port = 80
    }
  }
}

# Service NodePort para el admin: 2222 (Service) -> 22 (Pod),
# accesible desde fuera en <IP_worker1>:<admin_node_port>.
#
# externalTrafficPolicy = "Local":
#   - kube-proxy NO hace SNAT -> el Pod ve la IP real del cliente (host).
#   - Solo responde en los nodos que tienen un Pod admin (worker1).
#   Con "Cluster" (por defecto) la IP origen se cambiaría por la del nodo y la
#   NetworkPolicy con ipBlock del host no funcionaría.
resource "kubernetes_service_v1" "admin" {
  metadata {
    name      = "admin-svc"
    namespace = var.namespace
  }
  spec {
    type                    = "NodePort"
    selector                = local.admin_labels
    external_traffic_policy = "Local"
    port {
      name        = "ssh"
      protocol    = "TCP"
      port        = 2222
      target_port = 22
      node_port   = var.admin_node_port
    }
  }
}
