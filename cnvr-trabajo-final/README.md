# Trabajo final CNVR 2026-27

**Despliegue automático de una aplicación escalable sobre Kubernetes con Terraform**
Martín Luna Aguado y Brayan Guarachi Apaza

La guía completa (conceptos, pasos, pruebas y problemas típicos) está en **[GUIA.md](GUIA.md)**.

## Orden de ejecución

```bash
# HOST del laboratorio
./scripts/00-generar-claves.sh       # claves SSH (una sola vez)
./scripts/01-arranque-escenario.sh   # clúster k8s + VM terraform + copia a /shared
./scripts/02-vlan-workers.sh         # subinterfaces VLAN + Multus/Whereabouts
./scripts/03-arranque-lxc.sh         # LXC bbdd y logs (VNX)
# VM terraform
ssh root@10.10.10.13 'bash /shared/scripts/04-terraform-deploy.sh'
# HOST
./scripts/05-pruebas.sh              # pruebas para la memoria
./scripts/99-borrar.sh               # al terminar
```

| Carpeta | Contenido |
|---|---|
| `shared/` | Ficheros Terraform (se copian a `/mnt/tmp/k8s_lab-calico-v02/shared`) |
| `vnx/` | Escenario VNX con los contenedores LXC y sus ficheros de configuración |
| `scripts/` | Automatización (parámetros comunes en `scripts/config.sh`) |
