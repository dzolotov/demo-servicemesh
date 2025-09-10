#!/bin/bash

# Istio Service Mesh Deployment Script
# Автоматическая установка и настройка Istio с e-commerce demo

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
        docker build -t cart-service:latest services/cart/
    fi
    
    # Сборка catalog-service
    if [ -d "services/catalog" ]; then
        log_info "Сборка catalog-service..."
        docker build -t catalog-service:latest services/catalog/
    fi
    
    # Сборка api-gateway
    if [ -d "services/gateway" ]; then
        log_info "Сборка api-gateway..."
        docker build -t api-gateway:latest services/gateway/
    fi
    
    # Сборка payment-service (v1 и v2)
    if [ -d "services/payment" ]; then
        log_info "Сборка payment-service..."
        docker build -t payment-service:v1 -t payment-service:v2 services/payment/
    fi
    
    log_info "Docker образы успешно собраны ✓"
}

# Очистка от старых Service Mesh
cleanup_old_mesh() {
    log_info "Проверка и очистка старых Service Mesh..."
    
    # Проверка Linkerd
    if kubectl get namespace linkerd &> /dev/null; then
        log_warn "Обнаружен Linkerd. Удаляем..."
        
        # Удаление annotations
        for ns in $(kubectl get namespaces -o json | jq -r '.items[] | select(.metadata.annotations."linkerd.io/inject" == "enabled") | .metadata.name'); do
            kubectl annotate namespace $ns linkerd.io/inject-
        done
        
        # Удаление Linkerd
        if command -v linkerd &> /dev/null; then
            linkerd viz uninstall | kubectl delete -f - --ignore-not-found
            linkerd uninstall | kubectl delete -f - --ignore-not-found
        fi
        kubectl delete namespace linkerd linkerd-viz --ignore-not-found
    fi
    
    # Проверка старого Istio
    if kubectl get namespace istio-system &> /dev/null; then
        log_warn "Обнаружен старый Istio. Удаляем..."
        
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
    
    log_info "Очистка завершена ✓"
}

# Установка Istio CLI
install_istio_cli() {
    log_info "Установка Istio CLI..."
    
    if command -v istioctl &> /dev/null; then
        log_info "Istio CLI уже установлен"
        istioctl version --remote=false
    else
        log_info "Загрузка и установка Istio CLI..."
        
        # Определение архитектуры
        ARCH=$(uname -m)
        if [ "$ARCH" = "x86_64" ]; then
            ARCH="amd64"
        elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
            ARCH="arm64"
        fi
        
        # Определение ОС
        OS=$(uname | tr '[:upper:]' '[:lower:]')
        
        # Скачивание последней версии
        ISTIO_VERSION=$(curl -s https://api.github.com/repos/istio/istio/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
        
        log_info "Загрузка Istio $ISTIO_VERSION для $OS-$ARCH..."
        curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION TARGET_ARCH=$ARCH sh -
        
        # Добавление в PATH
        export PATH=$PWD/istio-${ISTIO_VERSION}/bin:$PATH
        
        # Проверка установки
        if ! command -v istioctl &> /dev/null; then
            log_error "Не удалось установить Istio CLI"
            exit 1
        fi
        
        log_info "Istio CLI установлен ✓"
        
        # Инструкция для постоянного использования
        echo ""
        log_warn "Для постоянного использования добавьте в ~/.bashrc или ~/.zshrc:"
        echo "export PATH=\$PATH:$PWD/istio-${ISTIO_VERSION}/bin"
        echo ""
    fi
}

# Предварительная проверка Istio
pre_check_istio() {
    log_info "Предварительная проверка совместимости..."
    
    if ! istioctl experimental precheck; then
        log_error "Предварительная проверка не пройдена. Исправьте ошибки и повторите."
        exit 1
    fi
    
    log_info "Предварительная проверка пройдена ✓"
}

# Установка Istio
install_istio() {
    log_info "Установка Istio с профилем demo..."
    
    # Установка с профилем demo (включает Ingress Gateway)
    istioctl install --set profile=demo -y
    
    # Ожидание готовности
    log_info "Ожидание готовности Istio control plane..."
    kubectl wait --for=condition=Ready pods --all -n istio-system --timeout=300s
    
    log_info "Istio установлен ✓"
}

# Установка дополнений Istio
install_istio_addons() {
    log_info "Установка дополнений Istio (Kiali, Prometheus, Grafana, Jaeger)..."
    
    # Проверка наличия samples
    if [ ! -d "istio-*/samples/addons" ]; then
        log_warn "Каталог samples/addons не найден. Загружаем манифесты..."
        
        # Загрузка манифестов дополнений
        kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/prometheus.yaml
        kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/grafana.yaml
        kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/jaeger.yaml
        kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/kiali.yaml
    else
        kubectl apply -f istio-*/samples/addons
    fi
    
    # Ожидание готовности
    log_info "Ожидание готовности дополнений..."
    kubectl wait --for=condition=Ready pods --all -n istio-system --timeout=300s || true
    
    log_info "Дополнения Istio установлены ✓"
}

# Проверка установки
verify_installation() {
    log_info "Проверка установки Istio..."
    
    # Используем analyze для проверки конфигурации
    if ! istioctl analyze --all-namespaces; then
        log_warn "Обнаружены предупреждения в конфигурации Istio"
    fi
    
    # Проверяем что все поды запущены
    if kubectl get pods -n istio-system | grep -E "0/[0-9]|Pending|Error|CrashLoopBackOff"; then
        log_error "Некоторые поды Istio не готовы"
        exit 1
    fi
    
    log_info "Установка Istio проверена ✓"
}

# Настройка namespace для e-commerce demo
setup_namespace() {
    log_info "Настройка namespace e-commerce..."
    
    # Создание namespace если не существует
    kubectl create namespace e-commerce --dry-run=client -o yaml | kubectl apply -f -
    
    # Включение автоматической инъекции sidecar
    kubectl label namespace e-commerce istio-injection=enabled --overwrite
    
    # Удаление старых annotations от Linkerd если есть
    kubectl annotate namespace e-commerce linkerd.io/inject- 2>/dev/null || true
    
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
    
    # Перезапуск deployments для инъекции sidecar
    log_info "Перезапуск deployments для инъекции Istio sidecar..."
    kubectl rollout restart deployment -n e-commerce
    
    # Ожидание готовности подов
    log_info "Ожидание готовности приложения..."
    kubectl wait --for=condition=Ready pods --all -n e-commerce --timeout=300s
    
    log_info "E-commerce demo развернут ✓"
}

# Применение Istio конфигураций
apply_istio_configs() {
    log_info "Применение Istio конфигураций..."
    
    # Проверка наличия конфигураций
    if [ ! -d "istio" ]; then
        log_warn "Каталог istio не найден. Пропускаем применение конфигураций."
        return
    fi
    
    # Применение VirtualServices, DestinationRules
    log_info "Применение VirtualServices и DestinationRules..."
    kubectl apply -f istio/virtual-services.yaml 2>/dev/null || true
    kubectl apply -f istio/destination-rules.yaml 2>/dev/null || true
    kubectl apply -f istio/gateway.yaml 2>/dev/null || true
    kubectl apply -f istio/peer-authentication.yaml 2>/dev/null || true
    
    # Применение политик авторизации (если есть финальный файл)
    if [ -f "istio/authorization-policies-final.yaml" ]; then
        log_info "Применение гранулярных политик авторизации..."
        kubectl apply -f istio/authorization-policies-final.yaml
        
        # Перезапуск подов для применения политик
        log_info "Перезапуск подов для применения политик RBAC..."
        kubectl rollout restart deployment -n e-commerce
        sleep 10
    else
        log_warn "Файл authorization-policies-final.yaml не найден, RBAC политики не применены"
    fi
    
    log_info "Istio конфигурации применены ✓"
}

# Создание Gateway для внешнего доступа
create_gateway() {
    log_info "Создание Istio Gateway для внешнего доступа..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: e-commerce-gateway
  namespace: e-commerce
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: e-commerce-vs
  namespace: e-commerce
spec:
  hosts:
  - "*"
  gateways:
  - e-commerce-gateway
  http:
  - match:
    - uri:
        prefix: "/api"
    route:
    - destination:
        host: api-gateway
        port:
          number: 5000
EOF
    
    log_info "Gateway создан ✓"
}

# Тестирование установки
test_installation() {
    log_info "Тестирование установки..."
    
    # Проверка подов
    log_info "Проверка подов в e-commerce namespace:"
    kubectl get pods -n e-commerce
    
    # Проверка инъекции sidecar
    local pod=$(kubectl get pods -n e-commerce -o name | head -1)
    if [ -n "$pod" ]; then
        local containers=$(kubectl get $pod -n e-commerce -o jsonpath='{.spec.containers[*].name}')
        if [[ $containers == *"istio-proxy"* ]]; then
            log_info "Istio sidecar успешно инжектирован ✓"
        else
            log_warn "Istio sidecar не найден в подах"
        fi
    fi
    
    # Получение GATEWAY_URL
    export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
    
    if [ -z "$INGRESS_HOST" ]; then
        log_info "LoadBalancer IP не назначен, используем NodePort..."
        export INGRESS_HOST=$(kubectl get po -l istio=ingressgateway -n istio-system -o jsonpath='{.items[0].status.hostIP}')
        export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
    fi
    
    export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT
    
    # Запуск port-forward для тестирования
    log_info "Запуск port-forward для API Gateway..."
    kubectl port-forward -n e-commerce svc/api-gateway 8080:5000 &
    local PF_PID=$!
    
    sleep 3
    
    # Тест API
    log_info "Тестирование API..."
    if curl -s http://localhost:8080/api/products | grep -q "products"; then
        log_info "API Gateway: /api/products работает корректно ✓"
    else
        log_warn "API не отвечает или работает некорректно. Возможна проблема с RBAC политиками."
        log_warn "Проверьте: kubectl get authorizationpolicy -n e-commerce"
    fi
    
    # Тест корзины
    if curl -s http://localhost:8080/api/cart/user123 | grep -q "cart"; then
        log_info "Cart Service: /api/cart работает корректно ✓"
    else
        log_warn "Cart API не отвечает"
    fi
    
    # Остановка port-forward
    kill $PF_PID 2>/dev/null || true
}

# Вывод информации о доступе
print_access_info() {
    echo ""
    log_info "========================================="
    log_info "Istio успешно установлен и настроен!"
    log_info "========================================="
    echo ""
    echo "Полезные команды:"
    echo ""
    echo "  # Открыть Kiali dashboard:"
    echo "  istioctl dashboard kiali"
    echo ""
    echo "  # Открыть Grafana:"
    echo "  istioctl dashboard grafana"
    echo ""
    echo "  # Открыть Jaeger:"
    echo "  istioctl dashboard jaeger"
    echo ""
    echo "  # Проверить конфигурацию:"
    echo "  istioctl analyze -n e-commerce"
    echo ""
    echo "  # Посмотреть proxy конфигурацию:"
    echo "  istioctl proxy-config all \$(kubectl get pod -n e-commerce -l app=gateway -o jsonpath='{.items[0].metadata.name}') -n e-commerce"
    echo ""
    echo "  # Доступ к API через Ingress Gateway:"
    if [ -n "$GATEWAY_URL" ]; then
        echo "  curl http://$GATEWAY_URL/api/products"
    else
        echo "  kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80"
        echo "  curl http://localhost:8080/api/products"
    fi
    echo ""
    echo "  # Прямой доступ к API Gateway:"
    echo "  kubectl port-forward -n e-commerce svc/api-gateway 8080:5000"
    echo "  curl http://localhost:8080/api/products"
    echo ""
    echo "  # Проверка RBAC политик:"
    echo "  kubectl get authorizationpolicy -n e-commerce"
    echo ""
    echo "  # Диагностика проблем с RBAC:"
    echo "  kubectl logs -n e-commerce deployment/api-gateway -c istio-proxy --tail=20"
    echo ""
    echo "  # Применение политик авторизации:"
    echo "  kubectl apply -f istio/authorization-policies-final.yaml"
    echo "  kubectl rollout restart deployment -n e-commerce"
    echo ""
}

# Главная функция
main() {
    echo ""
    log_info "========================================="
    log_info "Начало установки Istio Service Mesh"
    log_info "========================================="
    echo ""
    
    check_prerequisites
    build_docker_images
    cleanup_old_mesh
    install_istio_cli
    pre_check_istio
    install_istio
    install_istio_addons
    verify_installation
    setup_namespace
    deploy_demo
    apply_istio_configs
    create_gateway
    test_installation
    print_access_info
}

# Запуск
main
