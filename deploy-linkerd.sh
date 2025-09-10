#!/bin/bash

# Linkerd Service Mesh Deployment Script
# Автоматическая установка и настройка Linkerd с e-commerce demo

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
    
    # Проверка Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker не установлен. Установите Docker и повторите попытку."
        exit 1
    fi
    
    # Проверка подключения к кластеру
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Не удается подключиться к Kubernetes кластеру. Проверьте kubeconfig."
        exit 1
    fi
    
    log_info "Все необходимые компоненты установлены ✓"
}

# Сборка Docker образов
build_docker_images() {
    log_info "Сборка Docker образов для сервисов..."
    
    # Проверка наличия директории services
    if [ ! -d "services" ]; then
        log_error "Директория services не найдена. Запустите скрипт из корня проекта."
        exit 1
    fi
    
    # Сборка cart-service
    if [ -d "services/cart" ]; then
        log_info "Сборка cart-service..."
        docker build -t cart-service:v1 services/cart/
        docker build -t cart-service:latest services/cart/
    fi
    
    # Сборка catalog-service
    if [ -d "services/catalog" ]; then
        log_info "Сборка catalog-service..."
        docker build -t catalog-service:v1 services/catalog/
    fi
    
    # Сборка api-gateway
    if [ -d "services/gateway" ]; then
        log_info "Сборка api-gateway..."
        docker build -t api-gateway:v1 services/gateway/
    fi
    
    # Сборка payment-service (v1 и v2)
    if [ -d "services/payment" ]; then
        log_info "Сборка payment-service..."
        docker build -t payment-service:v1 services/payment/
        docker build -t payment-service:v2 --build-arg SERVICE_VERSION=v2 services/payment/
    fi
    
    log_info "Docker образы успешно собраны ✓"
}

# Очистка от старых Service Mesh
cleanup_old_mesh() {
    log_info "Проверка и очистка старых Service Mesh..."
    
    # Проверка Istio
    if kubectl get namespace istio-system &> /dev/null; then
        log_warn "Обнаружен Istio. Удаляем..."
        
        # Удаление label injection
        for ns in $(kubectl get namespaces -l istio-injection=enabled -o name | cut -d/ -f2); do
            kubectl label namespace $ns istio-injection-
        done
        
        # Удаление Istio
        if command -v istioctl &> /dev/null; then
            istioctl uninstall --purge -y
        fi
        kubectl delete namespace istio-system --ignore-not-found
    fi
    
    # Проверка старого Linkerd
    if kubectl get namespace linkerd &> /dev/null; then
        log_warn "Обнаружен старый Linkerd. Удаляем..."
        
        # Удаление annotations
        for ns in $(kubectl get namespaces -o json | jq -r '.items[] | select(.metadata.annotations."linkerd.io/inject" == "enabled") | .metadata.name'); do
            kubectl annotate namespace $ns linkerd.io/inject-
        done
        
        # Удаление Linkerd
        if command -v linkerd &> /dev/null; then
            linkerd viz uninstall | kubectl delete -f - --ignore-not-found
            linkerd uninstall --force | kubectl delete -f - --ignore-not-found
        fi
        kubectl delete namespace linkerd linkerd-viz --ignore-not-found
    fi
    
    log_info "Очистка завершена ✓"
}

# Установка Linkerd CLI
install_linkerd_cli() {
    log_info "Установка Linkerd CLI..."
    
    if command -v linkerd &> /dev/null; then
        log_info "Linkerd CLI уже установлен"
        linkerd version --client
    else
        log_info "Загрузка и установка Linkerd CLI..."
        curl -fsL https://run.linkerd.io/install-edge | sh
        
        # Добавление в PATH
        export PATH=$PATH:$HOME/.linkerd2/bin
        
        # Проверка установки
        if ! command -v linkerd &> /dev/null; then
            log_error "Не удалось установить Linkerd CLI"
            exit 1
        fi
        
        log_info "Linkerd CLI установлен ✓"
        
        # Добавление в .bashrc/.zshrc для постоянного использования
        echo 'export PATH=$PATH:$HOME/.linkerd2/bin' >> ~/.bashrc
        echo 'export PATH=$PATH:$HOME/.linkerd2/bin' >> ~/.zshrc 2>/dev/null || true
    fi
}

# Установка Gateway API CRDs
install_gateway_api() {
    log_info "Установка Gateway API CRDs (требуется для HTTPRoute)..."
    
    kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
    
    # Ожидание готовности CRDs
    kubectl wait --for condition=established --timeout=60s \
        crd/gateways.gateway.networking.k8s.io \
        crd/httproutes.gateway.networking.k8s.io \
        crd/referencegrants.gateway.networking.k8s.io
    
    log_info "Gateway API CRDs установлены ✓"
}

# Предварительная проверка Linkerd
pre_check_linkerd() {
    log_info "Предварительная проверка совместимости..."
    
    if ! linkerd check --pre; then
        log_error "Предварительная проверка не пройдена. Исправьте ошибки и повторите."
        exit 1
    fi
    
    log_info "Предварительная проверка пройдена ✓"
}

# Установка Linkerd Control Plane
install_linkerd() {
    log_info "Установка Linkerd Control Plane..."
    
    # Установка CRDs
    log_info "Установка Linkerd CRDs..."
    linkerd install --crds | kubectl apply -f -
    
    # Ожидание CRDs
    kubectl wait --for condition=established --timeout=60s \
        crd/servers.policy.linkerd.io \
        crd/serverauthorizations.policy.linkerd.io
    
    # Установка control plane с поддержкой Docker runtime
    log_info "Установка Linkerd control plane..."
    linkerd install --set proxyInit.runAsRoot=true | kubectl apply -f -
    
    # Ожидание готовности control plane
    log_info "Ожидание готовности control plane..."
    kubectl wait --for=condition=Ready pods --all -n linkerd --timeout=300s
    
    log_info "Linkerd control plane установлен ✓"
}

# Установка Linkerd Viz
install_linkerd_viz() {
    log_info "Установка Linkerd Viz для мониторинга..."
    
    linkerd viz install | kubectl apply -f -
    
    # Ожидание готовности viz
    log_info "Ожидание готовности Linkerd Viz..."
    kubectl wait --for=condition=Ready pods --all -n linkerd-viz --timeout=300s
    
    log_info "Linkerd Viz установлен ✓"
}

# Проверка установки
verify_installation() {
    log_info "Проверка установки Linkerd..."
    
    if ! linkerd check; then
        log_error "Проверка Linkerd не пройдена"
        exit 1
    fi
    
    if ! linkerd viz check; then
        log_warn "Проверка Linkerd Viz не пройдена полностью (это нормально)"
    fi
    
    log_info "Установка Linkerd проверена ✓"
}

# Настройка namespace для e-commerce demo
setup_namespace() {
    log_info "Настройка namespace e-commerce..."
    
    # Создание namespace если не существует
    kubectl create namespace e-commerce --dry-run=client -o yaml | kubectl apply -f -
    
    # Включение автоматической инъекции proxy
    kubectl annotate namespace e-commerce linkerd.io/inject=enabled --overwrite
    
    # Удаление старых labels от Istio если есть
    kubectl label namespace e-commerce istio-injection- 2>/dev/null || true
    
    log_info "Namespace e-commerce настроен ✓"
}

# Развертывание e-commerce demo
deploy_demo() {
    log_info "Развертывание e-commerce demo приложения..."
    
    # Проверка наличия манифестов
    if [ ! -d "kubernetes" ]; then
        log_error "Каталог kubernetes не найден. Запустите скрипт из каталога e-commerce-demo"
        exit 1
    fi
    
    # Применение базовых манифестов
    kubectl apply -f kubernetes/
    
    # Развертывание Redis для хранения корзин
    log_info "Развертывание Redis для хранения данных корзин..."
    kubectl apply -f kubernetes/redis-deployment.yaml 2>/dev/null || log_warn "Redis уже развернут"
    
    # Перезапуск deployments для инъекции proxy
    log_info "Перезапуск deployments для инъекции Linkerd proxy..."
    kubectl rollout restart deployment -n e-commerce
    
    # Ожидание готовности подов
    log_info "Ожидание готовности приложения..."
    kubectl wait --for=condition=Ready pods --all -n e-commerce --timeout=300s
    
    log_info "E-commerce demo развернут ✓"
}

# Применение Linkerd конфигураций
apply_linkerd_configs() {
    log_info "Применение Linkerd конфигураций..."
    
    # Проверка наличия конфигураций
    if [ ! -d "linkerd" ]; then
        log_warn "Каталог linkerd не найден. Пропускаем применение конфигураций."
        return
    fi
    
    # Применение ServiceProfiles и ServerAuthorizations
    kubectl apply -f linkerd/
    
    log_info "Linkerd конфигурации применены ✓"
}

# Создание HTTPRoute для канареечных развертываний
create_httproute() {
    log_info "Создание HTTPRoute для канареечного развертывания..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: payment-canary
  namespace: e-commerce
spec:
  parentRefs:
  - name: payment-service
    namespace: e-commerce
  rules:
  - backendRefs:
    - name: payment-service
      port: 5003
      weight: 95
    - name: payment-service-v2
      port: 5003
      weight: 5
EOF
    
    log_info "HTTPRoute создан ✓"
}

# Тестирование установки
test_installation() {
    log_info "Тестирование установки..."
    
    # Проверка подов
    log_info "Проверка подов в e-commerce namespace:"
    kubectl get pods -n e-commerce
    
    # Проверка инъекции proxy
    local pod=$(kubectl get pods -n e-commerce -o name | head -1)
    if [ -n "$pod" ]; then
        local containers=$(kubectl get $pod -n e-commerce -o jsonpath='{.spec.containers[*].name}')
        if [[ $containers == *"linkerd-proxy"* ]]; then
            log_info "Linkerd proxy успешно инжектирован ✓"
        else
            log_warn "Linkerd proxy не найден в подах"
        fi
    fi
    
    # Запуск port-forward для тестирования
    log_info "Запуск port-forward для API Gateway..."
    kubectl port-forward -n e-commerce svc/api-gateway 8080:5000 &
    local PF_PID=$!
    
    sleep 3
    
    # Тест API
    log_info "Тестирование API..."
    if curl -s http://localhost:8080/api/products | grep -q "products"; then
        log_info "API работает корректно ✓"
    else
        log_warn "API не отвечает или работает некорректно"
    fi
    
    # Остановка port-forward
    kill $PF_PID 2>/dev/null || true
}

# Вывод информации о доступе
print_access_info() {
    echo ""
    log_info "========================================="
    log_info "Linkerd успешно установлен и настроен!"
    log_info "========================================="
    echo ""
    echo "Полезные команды:"
    echo ""
    echo "  # Открыть Linkerd dashboard:"
    echo "  linkerd viz dashboard"
    echo ""
    echo "  # Проверить статус:"
    echo "  linkerd check"
    echo ""
    echo "  # Посмотреть метрики:"
    echo "  linkerd viz stat -n e-commerce deploy"
    echo ""
    echo "  # Посмотреть трафик в реальном времени:"
    echo "  linkerd viz tap -n e-commerce deploy/api-gateway"
    echo ""
    echo "  # Доступ к API Gateway:"
    echo "  kubectl port-forward -n e-commerce svc/api-gateway 8080:5000"
    echo "  curl http://localhost:8080/api/products"
    echo ""
}

# Главная функция
main() {
    echo ""
    log_info "========================================="
    log_info "Начало установки Linkerd Service Mesh"
    log_info "========================================="
    echo ""
    
    check_prerequisites
    build_docker_images
    cleanup_old_mesh
    install_linkerd_cli
    install_gateway_api
    pre_check_linkerd
    install_linkerd
    install_linkerd_viz
    verify_installation
    setup_namespace
    deploy_demo
    apply_linkerd_configs
    create_httproute
    test_installation
    print_access_info
}

# Запуск
main