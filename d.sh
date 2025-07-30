#!/bin/bash

set -e

# 1. 并发强制删除所有非系统/网络命名空间
echo "====== 1. 并发强制删除所有非系统/网络命名空间 ======"
kubectl get ns --no-headers | awk '{print $1}' | \
grep -vE '^(kube-system|kube-public|kube-node-lease|default|calico-system|tigera-operator|kube-flannel|cilium|weave|kube-ovn|istio-system)$' | \
xargs -r -P 20 -I {} kubectl delete ns {} --grace-period=0 --force &

# 2. 并发强制删除 default 下所有资源类型
echo "====== 2. 并发强制删除 default 下所有资源类型 ======"
kubectl api-resources --namespaced=true -o name | \
xargs -r -n 1 -P 20 -I {} kubectl delete {} --all -n default --grace-period=0 --force &

wait

# 3. 强制 patch 卡住的资源（Terminating 状态）
echo "====== 3. Patch 清理卡住的资源（Terminating） ======"
for kind in pod deployment replicaset statefulset daemonset job cronjob; do
  for name in $(kubectl get $kind -n default --no-headers 2>/dev/null | awk '{print $1}'); do
    kubectl patch $kind $name -n default -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
  done
done

# 4. 强制 patch 卡住的命名空间
echo "====== 4. Patch 清理卡住的命名空间（Terminating） ======"
for ns in $(kubectl get ns --no-headers | awk '/Terminating/ {print $1}'); do
  kubectl patch ns $ns -p '{"spec":{"finalizers":[]}}' --type=merge 2>/dev/null || true
done

echo "====== 5. 清理完成 ======"
