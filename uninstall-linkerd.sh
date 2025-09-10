#!/bin/bash

# Linkerd Service Mesh Uninstall Script
# Полное удаление Linkerd и очистка ресурсов

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
        kubectl delete all --all -n e-commerce --ignore-not-found
        
        # Удаление конфигураций Linkerd
        kubectl delete httproute --all -n e-commerce --ignore-not-found
        kubectl delete serviceprofile --all -n e-commerce --ignore-not-found
        kubectl delete serverauthorization --all -n e-commerce --ignore-not-found
        kubectl delete server --all -n e-commerce --ignore-not-found
        
        # Удаление ConfigMaps и Secrets
        kubectl delete configmap --all -n e-commerce --ignore-not-found
        kubectl delete secret --all -n e-commerce --ignore-not-found
        
        log_info "Ресурсы e-commerce удалены ✓"
    else
        log_info "Namespace e-commerce не найден"
    fi
}

# Удаление Linkerd annotations из namespaces
remove_linkerd_annotations() {
    log_info "Удаление Linkerd annotations из namespaces..."
    
    # Поиск и очистка namespaces с Linkerd annotations
    for ns in $(kubectl get namespaces -o json | jq -r '.items[] | select(.metadata.annotations."linkerd.io/inject" == "enabled") | .metadata.name'); do
        log_info "Удаление Linkerd annotation из namespace: $ns"
        kubectl annotate namespace $ns linkerd.io/inject-
    done
    
    log_info "Linkerd annotations удалены ✓"
}

# Удаление Linkerd Viz
uninstall_linkerd_viz() {
    log_info "Удаление Linkerd Viz..."
    
    if kubectl get namespace linkerd-viz &> /dev/null; then
        if command -v linkerd &> /dev/null; then
            log_info "Используем linkerd CLI для удаления Viz..."
            linkerd viz uninstall | kubectl delete -f - --ignore-not-found
        else
            log_info "linkerd CLI не найден, удаляем namespace напрямую..."
            kubectl delete namespace linkerd-viz --ignore-not-found
        fi
        
        # Ожидание удаления namespace
        log_info "Ожидание удаления linkerd-viz namespace..."
        kubectl wait --for=delete namespace/linkerd-viz --timeout=60s 2>/dev/null || true
        
        log_info "Linkerd Viz удален ✓"
    else
        log_info "Linkerd Viz не установлен"
    fi
}

# Удаление Linkerd Control Plane
uninstall_linkerd() {
    log_info "Удаление Linkerd Control Plane..."
    
    if kubectl get namespace linkerd &> /dev/null; then
        if command -v linkerd &> /dev/null; then
            log_info "Используем linkerd CLI для удаления..."
            linkerd uninstall | kubectl delete -f - --ignore-not-found
        else
            log_info "linkerd CLI не найден, удаляем ресурсы напрямую..."
            
            # Удаление всех Linkerd CRDs
            log_info "Удаление всех Linkerd CRDs..."
            kubectl delete crd authorizationpolicies.policy.linkerd.io --ignore-not-found
            kubectl delete crd egressnetworks.policy.linkerd.io --ignore-not-found
            kubectl delete crd externalworkloads.workload.linkerd.io --ignore-not-found
            kubectl delete crd httplocalratelimitpolicies.policy.linkerd.io --ignore-not-found
            kubectl delete crd httproutes.policy.linkerd.io --ignore-not-found
            kubectl delete crd meshtlsauthentications.policy.linkerd.io --ignore-not-found
            kubectl delete crd networkauthentications.policy.linkerd.io --ignore-not-found
            kubectl delete crd serverauthorizations.policy.linkerd.io --ignore-not-found
            kubectl delete crd servers.policy.linkerd.io --ignore-not-found
            kubectl delete crd serviceprofiles.linkerd.io --ignore-not-found
            
            # Удаление остальных CRDs через grep на случай если появились новые
            kubectl delete crd $(kubectl get crd -o name | grep linkerd.io | cut -d/ -f2) --ignore-not-found
            
            # Удаление namespace
            kubectl delete namespace linkerd --ignore-not-found
        fi
        
        # Ожидание удаления namespace
        log_info "Ожидание удаления linkerd namespace..."
        kubectl wait --for=delete namespace/linkerd --timeout=60s 2>/dev/null || true
        
        log_info "Linkerd Control Plane удален ✓"
    else
        log_info "Linkerd Control Plane не установлен"
    fi
}

# Удаление Gateway API CRDs (опционально)
remove_gateway_api() {
    read -p "Удалить Gateway API CRDs? Это может повлиять на другие приложения (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Удаление Gateway API CRDs..."
        
        kubectl delete crd gateways.gateway.networking.k8s.io --ignore-not-found
        kubectl delete crd gatewayclasses.gateway.networking.k8s.io --ignore-not-found
        kubectl delete crd httproutes.gateway.networking.k8s.io --ignore-not-found
        kubectl delete crd referencegrants.gateway.networking.k8s.io --ignore-not-found
        kubectl delete crd grpcroutes.gateway.networking.k8s.io --ignore-not-found
        kubectl delete crd tcproutes.gateway.networking.k8s.io --ignore-not-found
        kubectl delete crd tlsroutes.gateway.networking.k8s.io --ignore-not-found
        kubectl delete crd udproutes.gateway.networking.k8s.io --ignore-not-found
        
        log_info "Gateway API CRDs удалены ✓"
    else
        log_info "Gateway API CRDs оставлены"
    fi
}

# Удаление namespace e-commerce
remove_namespace() {
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

# Проверка остатков Linkerd
check_remnants() {
    log_info "Проверка остатков Linkerd..."
    
    # Проверка CRDs
    local crds=$(kubectl get crd -o name | grep linkerd.io | wc -l)
    if [ "$crds" -gt 0 ]; then
        log_warn "Найдены оставшиеся Linkerd CRDs:"
        kubectl get crd -o name | grep linkerd.io
    fi
    
    # Проверка namespaces
    if kubectl get namespace linkerd &> /dev/null; then
        log_warn "Namespace linkerd все еще существует"
    fi
    
    if kubectl get namespace linkerd-viz &> /dev/null; then
        log_warn "Namespace linkerd-viz все еще существует"
    fi
    
    # Проверка webhooks
    local webhooks=$(kubectl get mutatingwebhookconfigurations,validatingwebhookconfigurations -o name | grep linkerd | wc -l)
    if [ "$webhooks" -gt 0 ]; then
        log_warn "Найдены оставшиеся webhooks:"
        kubectl get mutatingwebhookconfigurations,validatingwebhookconfigurations -o name | grep linkerd
        
        log_info "Удаление webhooks..."
        kubectl delete mutatingwebhookconfigurations,validatingwebhookconfigurations -l linkerd.io/control-plane-ns=linkerd --ignore-not-found
    fi
    
    if [ "$crds" -eq 0 ] && [ "$webhooks" -eq 0 ]; then
        log_info "Linkerd полностью удален ✓"
    else
        log_warn "Найдены остатки Linkerd. Возможно, требуется ручная очистка."
    fi
}

# Вывод финальной информации
print_completion_info() {
    echo ""
    log_info "========================================="
    log_info "Удаление Linkerd завершено!"
    log_info "========================================="
    echo ""
    echo "Проверьте состояние кластера:"
    echo "  kubectl get namespaces"
    echo "  kubectl get crd | grep linkerd"
    echo ""
    echo "Если остались проблемные ресурсы, удалите их вручную:"
    echo "  kubectl patch namespace <name> -p '{\"metadata\":{\"finalizers\":[]}}' --type=merge"
    echo ""
}

# Главная функция
main() {
    echo ""
    log_info "========================================="
    log_info "Начало удаления Linkerd Service Mesh"
    log_info "========================================="
    echo ""
    
    check_prerequisites
    
    # Подтверждение удаления
    read -p "Вы уверены, что хотите удалить Linkerd и e-commerce demo? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Удаление отменено"
        exit 0
    fi
    
    remove_demo
    remove_linkerd_annotations
    uninstall_linkerd_viz
    uninstall_linkerd
    remove_gateway_api
    remove_namespace
    check_remnants
    print_completion_info
}

# Запуск
main