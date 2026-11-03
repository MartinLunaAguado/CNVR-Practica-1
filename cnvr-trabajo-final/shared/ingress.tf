# =============================================================================
# ingress.tf  (Apartado 4, punto 3 del enunciado)
# -----------------------------------------------------------------------------
# Las peticiones HTTP a /servers-GX se envían al Service web-svc:8080.
#
# rewrite-target "/" : el Ingress Controller reescribe /servers-GX -> / antes
# de mandar la petición a Nginx. Sin esto Nginx buscaría el fichero
# /servers-GX dentro de su web_root y devolvería 404.
# =============================================================================

resource "kubernetes_ingress_v1" "web" {
  metadata {
    name      = "web-ingress"
    namespace = var.namespace
    annotations = {
      "nginx.ingress.kubernetes.io/rewrite-target" = "/"
    }
  }

  spec {
    ingress_class_name = var.ingress_class

    rule {
      http {
        path {
          path      = local.ruta_ingress
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.web.metadata[0].name
              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }
}
