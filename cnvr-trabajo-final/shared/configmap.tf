# =============================================================================
# configmap.tf  (Apartado 3, punto 1 del enunciado)
# -----------------------------------------------------------------------------
# ConfigMap con la PLANTILLA index.html. La plantilla contiene el marcador
# __POD_NAME__, que el initContainer del Deployment sustituirá por el nombre
# real del Pod (también __NODE_NAME__ y __POD_IP__, como extra).
#
# templatefile() rellena aquí ${grupo} (en tiempo de Terraform). Los marcadores
# __XXX__ NO son sintaxis de Terraform, así que llegan intactos al ConfigMap.
# =============================================================================

resource "kubernetes_config_map_v1" "plantilla_web" {
  metadata {
    name      = "plantilla-web"
    namespace = var.namespace
  }
  data = {
    "index.html" = templatefile("${path.module}/html/index.html.tpl", {
      grupo = var.grupo
    })
  }
}
