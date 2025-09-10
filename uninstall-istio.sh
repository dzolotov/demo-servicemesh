#!/bin/bash

# Istio Service Mesh Uninstall Script
# Полное удаление Istio и очистка ресурсов

set -e  # Останавливаемся при ошибках

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция для вывода сообщений
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Проверка prerequisites
check_prerequisites() {
    log_info "Проверка необходимых компонентов..."
    
    # Проверка kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl не установлен. Установите kubectl и повторите попытку."
        exit 1
    fi
    
    # Проверка подключения к кластеру
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Не удается подключиться к Kubernetes кластеру. Проверьте kubeconfig."
        exit 1
    fi
    
    log_info "Все необходимые компоненты установлены ✓"
}

# Удаление e-commerce demo
remove_demo() {
    log_info "Удаление e-commerce demo приложения..."
    
    # Удаление всех ресурсов из namespace
    if kubectl get namespace e-commerce &> /dev/null; then
        log_info "Удаление всех ресурсов из namespace e-commerce..."
        
        # Удаление Istio конфигураций
        kubectl delete virtualservice --all -n e-commerce --ignore-not-found
        kubectl delete destinationrule --all -n e-commerce --ignore-not-found
        kubectl delete gateway --all -n e-commerce --ignore-not-found
        kubectl delete peerauthentication --all -n e-commerce --ignore-not-found
        kubectl delete authorizationpolicy --all -n e-commerce --ignore-not-found
        kubectl delete serviceentry --all -n e-commerce --ignore-not-found
        kubectl delete sidecar --all -n e-commerce --ignore-not-found
        kubectl delete telemetry --all -n e-commerce --ignore-not-found
        kubectl delete wasmplugin --all -n e-commerce --ignore-not-found
        
        # Удаление основных ресурсов
        kubectl delete all --all -n e-commerce --ignore-not-found
        
        # Удаление ConfigMaps и Secrets
        kubectl delete configmap --all -n e-commerce --ignore-not-found
        kubectl delete secret --all -n e-commerce --ignore-not-found
        
        log_info "Ресурсы e-commerce удалены ✓"
    else
        log_info "Namespace e-commerce не найден"
    fi
}

# Удаление Istio injection labels из namespaces
remove_istio_labels() {
    log_info "Удаление Istio injection labels из namespaces..."
    
    # Поиск и очистка namespaces с Istio injection
    for ns in $(kubectl get namespaces -l istio-injection=enabled -o name | cut -d/ -f2); do
        log_info "Удаление Istio injection label из namespace: $ns"
        kubectl label namespace $ns istio-injection-
    done
    
    # Также проверяем revision labels
    for ns in $(kubectl get namespaces -l istio.io/rev -o name | cut -d/ -f2); do
        log_info "Удаление Istio revision label из namespace: $ns"
        kubectl label namespace $ns istio.io/rev-
    done
    
    log_info "Istio labels удалены ✓"
}

# Удаление Istio дополнений
uninstall_istio_addons() {
    log_info "Удаление Istio дополнений (Kiali, Prometheus, Grafana, Jaeger)..."
    
    if kubectl get namespace istio-system &> /dev/null; then
        # Удаление deployments дополнений
        kubectl delete deployment kiali -n istio-system --ignore-not-found
        kubectl delete deployment prometheus -n istio-system --ignore-not-found
        kubectl delete deployment grafana -n istio-system --ignore-not-found
        kubectl delete deployment jaeger -n istio-system --ignore-not-found
        
        # Удаление services дополнений
        kubectl delete service kiali -n istio-system --ignore-not-found
        kubectl delete service prometheus -n istio-system --ignore-not-found
        kubectl delete service grafana -n istio-system --ignore-not-found
        kubectl delete service jaeger-collector -n istio-system --ignore-not-found
        kubectl delete service jaeger-query -n istio-system --ignore-not-found
        kubectl delete service tracing -n istio-system --ignore-not-found
        kubectl delete service zipkin -n istio-system --ignore-not-found
        
        # Удаление ConfigMaps дополнений
        kubectl delete configmap kiali -n istio-system --ignore-not-found
        kubectl delete configmap prometheus -n istio-system --ignore-not-found
        kubectl delete configmap grafana -n istio-system --ignore-not-found
        
        log_info "Istio дополнения удалены ✓"
    else
        log_info "Namespace istio-system не найден"
    fi
}

# Удаление Istio Control Plane
uninstall_istio() {
    log_info "Удаление Istio Control Plane..."
    
    if command -v istioctl &> /dev/null; then
        log_info "Используем istioctl для удаления..."
        
        # Получение установленных ревизий
        local revisions=$(istioctl tag list -o json 2>/dev/null | jq -r '.[].revision' 2>/dev/null || echo "")
        
        if [ -n "$revisions" ]; then
            for rev in $revisions; do
                log_info "Удаление ревизии: $rev"
                istioctl uninstall --revision=$rev -y --skip-confirmation
            done
        else
            # Удаление без указания ревизии
            istioctl uninstall --purge -y --skip-confirmation
        fi
        
        log_info "Istio Control Plane удален через istioctl ✓"
    else
        log_info "istioctl не найден, удаляем ресурсы напрямую..."
        
        # Удаление Istio deployments
        kubectl delete deployment -n istio-system --all --ignore-not-found
        kubectl delete daemonset -n istio-system --all --ignore-not-found
        kubectl delete service -n istio-system --all --ignore-not-found
        kubectl delete configmap -n istio-system --all --ignore-not-found
        kubectl delete secret -n istio-system --all --ignore-not-found
        
        log_info "Istio ресурсы удалены напрямую ✓"
    fi
}

# Удаление Istio CRDs
remove_istio_crds() {
    log_info "Удаление Istio CRDs..."
    
    # Список Istio CRDs
    local istio_crds=$(kubectl get crd -o name | grep istio.io)
    
    if [ -n "$istio_crds" ]; then
        echo "$istio_crds" | xargs kubectl delete --ignore-not-found
        log_info "Istio CRDs удалены ✓"
    else
        log_info "Istio CRDs не найдены"
    fi
}

# Удаление Istio webhooks
remove_istio_webhooks() {
    log_info "Удаление Istio webhooks..."
    
    # Удаление MutatingWebhookConfigurations
    kubectl delete mutatingwebhookconfiguration istio-sidecar-injector --ignore-not-found
    kubectl delete mutatingwebhookconfiguration istio-revision-tag-default --ignore-not-found
    
    # Удаление ValidatingWebhookConfigurations
    kubectl delete validatingwebhookconfiguration istio-validator --ignore-not-found
    kubectl delete validatingwebhookconfiguration istiod-default-validator --ignore-not-found
    
    # Удаление любых других Istio webhooks
    kubectl delete mutatingwebhookconfigurations -l app=sidecar-injector --ignore-not-found
    kubectl delete validatingwebhookconfigurations -l app=istiod --ignore-not-found
    
    log_info "Istio webhooks удалены ✓"
}

# Удаление Istio namespaces
remove_istio_namespaces() {
    log_info "Удаление Istio namespaces..."
    
    # Удаление istio-system
    if kubectl get namespace istio-system &> /dev/null; then
        kubectl delete namespace istio-system --ignore-not-found
        
        # Ожидание удаления
        log_info "Ожидание удаления namespace istio-system..."
        kubectl wait --for=delete namespace/istio-system --timeout=60s 2>/dev/null || true
    fi
    
    # Удаление istio-operator (если есть)
    if kubectl get namespace istio-operator &> /dev/null; then
        kubectl delete namespace istio-operator --ignore-not-found
        kubectl wait --for=delete namespace/istio-operator --timeout=60s 2>/dev/null || true
    fi
    
    log_info "Istio namespaces удалены ✓"
}

# Удаление namespace e-commerce
remove_demo_namespace() {
    log_info "Удаление namespace e-commerce..."
    
    if kubectl get namespace e-commerce &> /dev/null; then
        kubectl delete namespace e-commerce --ignore-not-found
        
        # Ожидание удаления
        log_info "Ожидание удаления namespace e-commerce..."
        kubectl wait --for=delete namespace/e-commerce --timeout=60s 2>/dev/null || true
        
        log_info "Namespace e-commerce удален ✓"
    else
        log_info "Namespace e-commerce не существует"
    fi
}

# Проверка остатков Istio
check_remnants() {
    log_info "Проверка остатков Istio..."
    
    local has_remnants=false
    
    # Проверка CRDs
    local crds=$(kubectl get crd -o name | grep istio.io | wc -l)
    if [ "$crds" -gt 0 ]; then
        log_warn "Найдены оставшиеся Istio CRDs:"
        kubectl get crd -o name | grep istio.io
        has_remnants=true
    fi
    
    # Проверка namespaces
    if kubectl get namespace istio-system &> /dev/null; then
        log_warn "Namespace istio-system все еще существует"
        has_remnants=true
    fi
    
    if kubectl get namespace istio-operator &> /dev/null; then
        log_warn "Namespace istio-operator все еще существует"
        has_remnants=true
    fi
    
    # Проверка webhooks
    local webhooks=$(kubectl get mutatingwebhookconfigurations,validatingwebhookconfigurations -o name | grep -i istio | wc -l)
    if [ "$webhooks" -gt 0 ]; then
        log_warn "Найдены оставшиеся webhooks:"
        kubectl get mutatingwebhookconfigurations,validatingwebhookconfigurations -o name | grep -i istio
        has_remnants=true
    fi
    
    # Проверка ClusterRoles и ClusterRoleBindings
    local rbac=$(kubectl get clusterroles,clusterrolebindings -o name | grep -i istio | wc -l)
    if [ "$rbac" -gt 0 ]; then
        log_warn "Найдены оставшиеся RBAC ресурсы:"
        kubectl get clusterroles,clusterrolebindings -o name | grep -i istio | head -5
        
        read -p "Удалить RBAC ресурсы Istio? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kubectl delete clusterroles,clusterrolebindings -l app=istio --ignore-not-found
            kubectl delete clusterroles,clusterrolebindings -l release=istio --ignore-not-found
        fi
    fi
    
    if [ "$has_remnants" = false ]; then
        log_info "Istio полностью удален ✓"
    else
        log_warn "Найдены остатки Istio. Возможно, требуется ручная очистка."
    fi
}

# Очистка finalizers для зависших namespaces
fix_stuck_namespaces() {
    local stuck_ns=$(kubectl get namespaces | grep Terminating | awk '{print $1}')
    
    if [ -n "$stuck_ns" ]; then
        log_warn "Найдены зависшие namespaces в состоянии Terminating:"
        echo "$stuck_ns"
        
        read -p "Попытаться исправить зависшие namespaces? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            for ns in $stuck_ns; do
                log_info "Исправление namespace: $ns"
                kubectl patch namespace $ns -p '{"metadata":{"finalizers":[]}}' --type=merge
            done
        fi
    fi
}

# Вывод финальной информации
print_completion_info() {
    echo ""
    log_info "========================================="
    log_info "Удаление Istio завершено!"
    log_info "========================================="
    echo ""
    echo "Проверьте состояние кластера:"
    echo "  kubectl get namespaces"
    echo "  kubectl get crd | grep istio"
    echo "  kubectl get mutatingwebhookconfigurations"
    echo "  kubectl get validatingwebhookconfigurations"
    echo ""
    echo "Если остались проблемные ресурсы, удалите их вручную:"
    echo "  kubectl delete crd <crd-name>"
    echo "  kubectl patch namespace <name> -p '{\"metadata\":{\"finalizers\":[]}}' --type=merge"
    echo ""
}

# Главная функция
main() {
    echo ""
    log_info "========================================="
    log_info "Начало удаления Istio Service Mesh"
    log_info "========================================="
    echo ""
    
    check_prerequisites
    
    # Подтверждение удаления
    read -p "Вы уверены, что хотите удалить Istio и e-commerce demo? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Удаление отменено"
        exit 0
    fi
    
    remove_demo
    remove_istio_labels
    uninstall_istio_addons
    uninstall_istio
    remove_istio_webhooks
    remove_istio_crds
    remove_istio_namespaces
    remove_demo_namespace
    fix_stuck_namespaces
    check_remnants
    print_completion_info
}

# Запуск
main