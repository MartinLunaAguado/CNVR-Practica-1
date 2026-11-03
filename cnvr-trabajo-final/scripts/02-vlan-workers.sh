#!/bin/bash
# =============================================================================
# 02-vlan-workers.sh  (ejecutar en el HOST)  -> Apartado 2, punto 1
# -----------------------------------------------------------------------------
# Crea en cada worker la subinterfaz VLAN (p.ej. eth2.100) sobre la interfaz
# conectada a VlanNet. Multus (macvlan) colgará de ella las interfaces net1
# de los Pods. Es lo mismo que en la P1.3, pero automatizado.
#
# También comprueba que Multus y Whereabouts están instalados.
# =============================================================================
set -e
source "$(dirname "$0")/config.sh"
SUBIF="${VLAN_PARENT_IF}.${VLAN_ID}"

for w in $WORKERS; do
  echo "== $w: creando $SUBIF"
  ssh -o StrictHostKeyChecking=accept-new root@"$w" "
    modprobe 8021q 2>/dev/null || true
    ip link set $VLAN_PARENT_IF up
    ip link show $SUBIF >/dev/null 2>&1 || \
      ip link add link $VLAN_PARENT_IF name $SUBIF type vlan id $VLAN_ID
    ip link set $SUBIF up
    ip -d link show $SUBIF | head -3
  "
done

echo "== Comprobando Multus (CRD NetworkAttachmentDefinition)"
kubectl get crd network-attachment-definitions.k8s.cni.cncf.io \
  || echo "!! Multus NO está instalado: instaladlo como en la P1.3"

echo "== Comprobando Whereabouts (IPAM para los Pods web)"
if ! kubectl get crd ippools.whereabouts.cni.cncf.io >/dev/null 2>&1; then
  echo "!! Whereabouts no está instalado. Instalándolo..."
  WB=https://raw.githubusercontent.com/k8snetworkplumbingwg/whereabouts/master/doc/crds
  kubectl apply -f $WB/daemonset-install.yaml \
                -f $WB/whereabouts.cni.cncf.io_ippools.yaml \
                -f $WB/whereabouts.cni.cncf.io_overlappingrangeipreservations.yaml
  kubectl -n kube-system rollout status ds/whereabouts --timeout=180s || true
fi
kubectl get pods -A | grep -E 'multus|whereabouts' || true
