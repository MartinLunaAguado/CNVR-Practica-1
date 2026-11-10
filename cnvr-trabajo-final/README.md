# Trabajo final CNVR 2026-27 · Grupo 9

**Despliegue automático de una aplicación escalable sobre Kubernetes con Terraform**
Martín Luna Aguado y Brayan Guarachi Apaza

Escenario: 3 servidores web (Deployment, imagen `dgsgiros/nginx-ssh`) y 1 servidor de
administración (imagen `dgsgiros/admin-ssh`) en un clúster Kubernetes con Calico, más
dos contenedores LXC (MariaDB y rsyslog) desplegados con VNX. Todos comparten la
VLAN 100 (`10.1.100.0/24`) mediante Multus.

## Estructura

| Carpeta | Contenido |
|---|---|
| `shared/` | Proyecto Terraform. Se copia a `/mnt/tmp/k8s_lab-calico-v02/shared` (= `/shared` en la máquina terraform) |
| `vnx/` | Escenario VNX con los contenedores LXC `bbdd` y `logs` y sus ficheros de configuración |
| `scripts/` | Scripts numerados en el orden de ejecución |

| Fichero Terraform | Apartado del enunciado |
|---|---|
| `k8s-provider.tf`, `variables.tf`, `terraform.tfvars`, `locals.tf`, `outputs.tf` | Base del proyecto |
| `secrets.tf` | 2.5 Claves SSH en Secrets (dos pares) |
| `multus.tf` | 2.3 NetworkAttachmentDefinition (kubernetes_manifest) |
| `configmap.tf`, `html/index.html.tpl` | 3.1 Plantilla HTML (y configuración del cliente SSH del admin) |
| `web-deployment.tf` | 3.2 y 3.3 Deployment web con initContainer y volúmenes |
| `admin-pod.tf` | 2 y 5.3 Pod admin (nodeSelector, fsGroup, claves) |
| `services.tf` | 4.1 y 4.2 Service ClusterIP y NodePort |
| `ingress.tf` | 4.3 Ingress `/servers-G9` |
| `network-policies.tf` | 5 NetworkPolicy |

## Despliegue

Antes de nada, confirmar los valores marcados con `<--` en `shared/terraform.tfvars`
y `scripts/config.sh` (los muestra `02-inspeccionar-imagenes.sh`).

```bash
# En el host del laboratorio
./scripts/00-generar-claves.sh          # dos pares de claves SSH
./scripts/01-arranque-escenario.sh      # Kubernetes + Calico + máquina terraform
./scripts/02-inspeccionar-imagenes.sh   # comprobaciones (no modifica nada)
./scripts/03-vlan-workers.sh            # subinterfaz VLAN en los workers, Multus, Whereabouts
./scripts/04-arranque-lxc.sh            # contenedores LXC bbdd y logs
ssh root@terraform 'bash /shared/scripts/05-terraform-deploy.sh'   # terraform init/plan/apply
./scripts/06-pruebas.sh                 # pruebas P1-P10 con [OK] / [FALLO]
./scripts/07-cliente-bd.sh              # opcional: cliente SQL en los Pods
./scripts/99-borrar.sh                  # copia de seguridad + terraform destroy + LXC
```

Todo seguido: `./scripts/desplegar-todo.sh` (o `--sin-k8s` si el clúster ya está arrancado).

## Accesos

| Acceso | Comando |
|---|---|
| Aplicación web | `curl http://<IP_o_puerto_del_Ingress>/servers-G9` |
| Host → admin | `ssh -i shared/keys/host_admin_rsa -p 30022 adminuser@10.10.10.11` |
| Admin → servidor web | `ssh <IP_VLAN_del_web>` (usuario `webuser`) |
| Admin → LXC | `ssh bbdd`, `ssh logs` (usuario `root`) |
| Base de datos | `mysql -h 10.1.100.21 -u cnvr -pcnvr2627 cnvr` |

## Direcciones

| Elemento | IP |
|---|---|
| Host (user_LAN) | 10.10.20.2 |
| k8s-master / worker1 / worker2 / terraform (k8s_LAN) | 10.10.10.10 / .11 / .12 / .13 |
| admin (VLAN) | 10.1.100.10 |
| Servidores web (VLAN) | 10.1.100.100 – 10.1.100.150 (Whereabouts) |
| bbdd / logs (VLAN) | 10.1.100.21 / 10.1.100.22 |
