#!/bin/bash
# =============================================================================
# 03-vlan-workers.sh  (HOST)  -> Apartado 2, pasos 2 y 3
# -----------------------------------------------------------------------------
# Crea en cada worker la subinterfaz VLAN (p.ej. eth2.100) sobre la interfaz
# conectada a VlanNet. De ella cuelgan (macvlan) las interfaces net1 que Multus
# añade a los Pods. Es el procedimiento de la práctica 1.3, automatizado.
#
# También comprueba que Multus está instalado e instala Whereabouts (el plugin
# que reparte las IP de la VLAN a los Pods web) si no lo está.
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
if ! kubectl get crd network-attachment-definitions.k8s.cni.cncf.io >/dev/null 2>&1; then
  echo "!! Multus NO está instalado. Instaladlo como en la práctica 1.3 y repetid."
  exit 1
fi
echo "   Multus OK"

echo "== Comprobando Whereabouts (IPAM de los Pods web)"
if ! kubectl get crd ippools.whereabouts.cni.cncf.io >/dev/null 2>&1; then
  echo "   No está instalado. Instalándolo..."
  WB=https://raw.githubusercontent.com/k8snetworkplumbingwg/whereabouts/master/doc/crds
  kubectl apply -f $WB/whereabouts.cni.cncf.io_ippools.yaml \
                -f $WB/whereabouts.cni.cncf.io_overlappingrangeipreservations.yaml \
                -f $WB/whereabouts.cni.cncf.io_nodeslicepools.yaml \
                -f $WB/daemonset-install.yaml
  kubectl -n kube-system rollout status ds/whereabouts --timeout=240s
fi
echo "   Whereabouts OK"
kubectl get pods -A -o wide | grep -Ei 'multus|whereabouts' || true
