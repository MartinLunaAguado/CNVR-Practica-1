#!/bin/bash
# =============================================================================
# 04-terraform-deploy.sh  (ejecutar DENTRO de la máquina "terraform")
#     ssh root@terraform   ->   bash /shared/scripts/04-terraform-deploy.sh
# -----------------------------------------------------------------------------
# (Este script se copia a /shared/scripts con 01-arranque-escenario.sh si
#  copiáis también la carpeta scripts; si no, ejecutad los comandos a mano.)
# =============================================================================
set -e
cd /shared

terraform init
terraform fmt -check || terraform fmt
terraform validate
terraform plan -out=plan.tfplan
terraform apply plan.tfplan

# Segunda lectura para que aparezcan las IPs VLAN de los Pods en los outputs
terraform apply -refresh-only -auto-approve
terraform output
