#!/bin/bash
# =============================================================================
# 05-terraform-deploy.sh  (DENTRO de la máquina "terraform")
#     ssh root@terraform 'bash /shared/scripts/05-terraform-deploy.sh'
# -----------------------------------------------------------------------------
# Despliega todos los recursos de Kubernetes con Terraform.
# (01-arranque-escenario.sh copia este script a /shared/scripts.)
# =============================================================================
set -e
cd /shared

for k in keys/admin_web_rsa keys/admin_web_rsa.pub keys/host_admin_rsa.pub; do
  [ -f "$k" ] || { echo "Falta /shared/$k: ejecutad 00-generar-claves.sh en el host y volved a copiar el proyecto"; exit 1; }
done

terraform init -input=false
terraform validate
terraform plan -input=false -out=plan.tfplan
terraform apply -input=false plan.tfplan

# Segunda lectura: las IP de la VLAN las anota Multus al arrancar cada Pod
terraform apply -refresh-only -auto-approve -input=false
terraform output
