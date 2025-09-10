# E-Commerce Service Mesh Demo

Демонстрационное приложение для изучения возможностей Service Mesh (Istio/Linkerd) на примере микросервисной e-commerce платформы.

## 🏗️ Архитектура

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Browser   │────▶│ API Gateway  │────▶│   Catalog   │
└─────────────┘     └──────┬───────┘     └─────────────┘
                           │
                           ▼
                    ┌──────────────┐     ┌─────────────┐
                    │     Cart     │────▶│   Payment   │
                    └──────────────┘     └─────────────┘
                                               v1 / v2
```

### Сервисы:
- **API Gateway** (port 5000) - единая точка входа
- **Catalog Service** (port 5001) - каталог товаров
- **Cart Service** (port 5002) - корзина покупок (использует Redis для хранения данных)
- **Payment Service** (port 5003) - обработка платежей (v1 и v2)
- **Redis** (port 6379) - хранилище данных корзины для консистентности между репликами

## Структура проекта

```
e-commerce-demo/
├── services/           # Python микросервисы
├── kubernetes/         # Базовые Kubernetes манифесты
├── istio/             # Конфигурация Istio Service Mesh
├── linkerd/           # Конфигурация Linkerd Service Mesh
└── monitoring/        # Prometheus и Grafana для мониторинга
```

## 🚀 Быстрый старт с автоматической установкой

### Скрипты для автоматизации

В проекте доступны следующие скрипты для быстрого развертывания:

| Скрипт | Описание |
|--------|----------|
| `./build.sh` | Сборка всех Docker образов |
| `./deploy-istio.sh` | Установка Istio с демо-приложением |
| `./deploy-linkerd.sh` | Установка Linkerd с демо-приложением |
| `./uninstall-istio.sh` | Полное удаление Istio |
| `./uninstall-linkerd.sh` | Полное удаление Linkerd |
| `./quick-test.sh` | Быстрое тестирование установки |

### Автоматическая установка Istio

```bash
# Запустить автоматическую установку Istio с демо-приложением
./deploy-istio.sh
```

Скрипт автоматически:
- ✅ Проверит prerequisites
- ✅ Удалит старые Service Mesh (Linkerd, старый Istio)  
- ✅ Установит Istio CLI
- ✅ Развернет Istio с профилем demo
- ✅ Установит дополнения (Kiali, Grafana, Jaeger, Prometheus)
- ✅ Создаст ServiceAccounts для всех сервисов
- ✅ Развернет e-commerce приложение
- ✅ Настроит Gateway для внешнего доступа
- ✅ Протестирует установку

### Автоматическая установка Linkerd

```bash
# Запустить автоматическую установку Linkerd с демо-приложением
./deploy-linkerd.sh
```

Скрипт автоматически:
- ✅ Проверит prerequisites
- ✅ Удалит старые Service Mesh
- ✅ Установит Linkerd CLI
- ✅ Развернет Linkerd control plane
- ✅ Установит Viz extension для мониторинга
- ✅ Создаст ServiceAccounts
- ✅ Развернет e-commerce приложение с автоматической инъекцией proxy
- ✅ Протестирует установку

## Быстрый старт

### 1. Сборка Docker образов

**Автоматическая сборка (рекомендуется):**
```bash
# Скрипт автоматически собирает все образы
./build.sh
```

**Ручная сборка:**
```bash
# Сборка образа каталога
docker build -t catalog-service:v1 ./services/catalog/

# Сборка образа корзины
docker build -t cart-service:v1 ./services/cart/

# Сборка образа API Gateway
docker build -t api-gateway:v1 ./services/gateway/

# Сборка образов платежного сервиса
docker build -t payment-service:v1 ./services/payment/
docker build -t payment-service:v2 --build-arg SERVICE_VERSION=v2 ./services/payment/

# Для OrbStack - пуш в локальный registry
docker tag catalog-service:v1 localhost:5001/catalog-service:v1
docker push localhost:5001/catalog-service:v1
# Повторить для всех сервисов
```

### 2. Развертывание в Kubernetes

```bash
# Создание namespace
kubectl apply -f kubernetes/namespace.yaml

# Развертывание сервисов
kubectl apply -f kubernetes/
```

### 3. Выбор Service Mesh

**Важно:** Используйте только один Service Mesh - либо Istio, либо Linkerd, но не оба одновременно!

#### Установка Istio

**Автоматическая установка (рекомендуется):**
```bash
./deploy-istio.sh
```

**Удаление Istio:**
```bash
./uninstall-istio.sh
```

**Ручная установка:**
```bash
# Скачать и установить Istio
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH

# Предварительная проверка
istioctl experimental precheck

# Установка Istio с demo профилем
istioctl install --set profile=demo -y

# Создание ServiceAccounts
kubectl apply -f kubernetes/service-accounts.yaml

# Включить автоматическую инъекцию sidecar для namespace
kubectl label namespace e-commerce istio-injection=enabled

# Применение Istio конфигурации
kubectl apply -f istio/

# Проверка установки
istioctl analyze --all-namespaces
```

#### Установка Linkerd (альтернатива Istio)

**Автоматическая установка (рекомендуется):**
```bash
./deploy-linkerd.sh
```

**Удаление Linkerd:**
```bash
./uninstall-linkerd.sh
```

**Ручная установка:**
```bash
# Скачать и установить Linkerd CLI
curl -fsL https://run.linkerd.io/install-edge | sh
export PATH=$PATH:$HOME/.linkerd2/bin

# Установить Gateway API CRDs (требуется для Linkerd)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml

# Предварительная проверка
linkerd check --pre

# Установка Linkerd CRDs
linkerd install --crds | kubectl apply -f -

# Установка control plane (с поддержкой Docker runtime)
linkerd install --set proxyInit.runAsRoot=true | kubectl apply -f -

# Включить автоматическую инъекцию proxy для namespace
kubectl annotate namespace e-commerce linkerd.io/inject=enabled

# Установка Viz extension для мониторинга
linkerd viz install | kubectl apply -f -

# Применение Linkerd конфигурации (если есть)
kubectl apply -f linkerd/

# Проверка установки
linkerd check
linkerd viz check
```

**Примечание:** Для точного управления трафиком в Linkerd установите также Gateway API CRDs выше.

#### Современные подходы к канареечным развертываниям в Linkerd

**Способ 1: Через количество реплик (простой)**
```bash
# Настройка канареечного развертывания 95%:5%
kubectl scale deployment payment-service-v1 --replicas=19  # 95% трафика
kubectl scale deployment payment-service-v2 --replicas=1   # 5% трафика
```

**Способ 2: Через HTTPRoute (точный)**
```bash
# Создание HTTPRoute для точного распределения трафика
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: payment-canary
  namespace: e-commerce
spec:
  parentRefs:
  - name: payment-service
  rules:
  - backendRefs:
    - name: payment-service-v1
      weight: 95
    - name: payment-service-v2
      weight: 5
EOF
```

**Способ 3: Через Flagger (автоматический)**
```bash
# Установка Flagger для автоматических канареечных релизов
kubectl apply -k github.com/fluxcd/flagger/kustomize/linkerd

# Создание Canary ресурса
kubectl apply -f - <<EOF
apiVersion: flagger.app/v1beta1
kind: Canary
metadata:
  name: payment-service
  namespace: e-commerce
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: payment-service
  service:
    port: 5003
  analysis:
    interval: 30s
    threshold: 5
    maxWeight: 50
    stepWeight: 10
    metrics:
    - name: request-success-rate
      threshold: 99
EOF
```

### 5. Установка мониторинга

```bash
kubectl apply -f monitoring/
```

## Возможности демонстрации

### Canary Deployment
- Payment Service развернут в двух версиях (v1 и v2)
- Istio: 95% трафика на v1, 5% на v2 через VirtualService
- Linkerd: распределение через replicas (95%:5%) или HTTPRoute (Gateway API)

### Circuit Breaker
- Автоматическое исключение неисправных инстансов
- Настроено через DestinationRule (Istio) и ServiceProfile (Linkerd)

### Retry и Timeout
- Автоматические повторы при сбоях (кроме POST запросов)
- Таймауты для предотвращения зависаний

### mTLS
- Шифрование трафика между сервисами
- Zero-trust security модель

### Observability
- Метрики в Prometheus
- Визуализация в Grafana
- Distributed tracing (при подключении Jaeger)

## Тестирование

### Проверка работоспособности

```bash
# Проверка здоровья сервисов
kubectl get pods -n e-commerce

# Получение списка товаров
kubectl port-forward -n e-commerce svc/catalog-service 5001:5001
curl http://localhost:5001/products

# Добавление товара в корзину
kubectl port-forward -n e-commerce svc/cart-service 5002:5002
curl -X POST http://localhost:5002/cart/user123/add \
  -H "Content-Type: application/json" \
  -d '{"product_id": "1", "quantity": 2}'
```

### Проверка Service Mesh функций

```bash
# Просмотр метрик Istio
kubectl -n istio-system port-forward svc/prometheus 9090:9090

# Просмотр дашборда Grafana  
kubectl -n e-commerce port-forward svc/grafana 3000:3000
# Логин: admin / admin

# Проверка mTLS
istioctl authn tls-check payment-service.e-commerce.svc.cluster.local
```

## Демонстрация сбоев и восстановления

### Имитация случайных ошибок
Сервисы настроены на случайные сбои:
- Catalog Service: 5% вероятность 500 ошибки
- Payment Service: 10% вероятность отклонения платежа, 5% вероятность таймаута

### Наблюдение за circuit breaker
При превышении порога ошибок, Service Mesh автоматически исключит проблемный инстанс из балансировки.

## Очистка

### Удаление приложения
```bash
# Удаление приложения (сохраняет Service Mesh)
kubectl delete namespace e-commerce
```

### Полное удаление Istio
```bash
# Сначала удалить приложения и конфигурацию
kubectl delete namespace e-commerce

# Удалить Istio control plane
istioctl uninstall --purge -y

# Удалить остаточные CRDs и webhook configurations
kubectl delete validatingwebhookconfiguration istio-validator-istio-system
kubectl delete mutatingwebhookconfiguration istio-sidecar-injector

# Проверить что все удалено
kubectl get namespace istio-system
```

### Полное удаление Linkerd
```bash
# Сначала удалить приложения
kubectl delete namespace e-commerce

# Удалить Viz extension
linkerd viz uninstall | kubectl delete -f -

# Удалить Linkerd control plane
linkerd uninstall | kubectl delete -f -

# Удалить Gateway API CRDs (если больше не нужны)
kubectl delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml

# Проверить что все удалено
kubectl get namespace linkerd linkerd-viz
```

### Переключение между Service Mesh
```bash
# Переход с Istio на Linkerd:
# 1. Удалить Istio конфигурацию
kubectl delete -f istio/
# 2. Удалить label injection и добавить annotation
kubectl label namespace e-commerce istio-injection-
kubectl annotate namespace e-commerce linkerd.io/inject=enabled
# 3. Установить Linkerd (см. инструкции выше)
# 4. Перезапустить поды
kubectl rollout restart deployment -n e-commerce

# Переход с Linkerd на Istio:
# 1. Удалить Linkerd конфигурацию  
kubectl delete -f linkerd/
# 2. Удалить annotation и добавить label
kubectl annotate namespace e-commerce linkerd.io/inject-
kubectl label namespace e-commerce istio-injection=enabled
# 3. Установить Istio (см. инструкции выше)
# 4. Перезапустить поды
kubectl rollout restart deployment -n e-commerce
```

## 🔐 Настройка RBAC и авторизации в Istio

### Гранулярные политики авторизации

После установки Istio необходимо настроить правильные политики авторизации для защиты микросервисов:

```bash
# Применение гранулярных политик авторизации
kubectl apply -f istio/authorization-policies-final.yaml
```

#### Архитектура безопасности

```
┌──────────────┐
│   Internet   │
└──────┬───────┘
       │ 
┌──────▼───────┐     ┌────────────┐
│Ingress Gateway├────►│API Gateway │ ✅ Разрешён внешний доступ
└──────────────┘     └─────┬──────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
   ┌────▼─────┐     ┌────▼─────┐     ┌────▼─────┐
   │ Catalog  │     │   Cart   │     │Notification│
   │ Service  │     │ Service  │     │  Service   │
   └──────────┘     └─────┬────┘     └────────────┘
                          │
                    ┌─────▼─────┐
                    │  Payment  │ ❌ Доступ только от Cart Service
                    │  Service  │
                    └───────────┘
```

#### Настроенные политики

1. **API Gateway** 
   - ✅ Принимает трафик от Istio Ingress Gateway
   - ✅ Принимает внешний трафик на `/api/*`
   - ✅ Health checks доступны всем

2. **Catalog Service**
   - ✅ Доступен для API Gateway (публичные запросы)
   - ✅ Доступен для Cart Service (получение информации о товарах)
   - ❌ Блокирует прямой внешний доступ

3. **Cart Service**
   - ✅ Доступен только для API Gateway
   - ❌ Блокирует прямой внешний доступ

4. **Payment Service** (самый защищённый)
   - ✅ Доступен только для Cart Service
   - ❌ Блокирует доступ от API Gateway
   - ❌ Блокирует любой внешний доступ

5. **Notification Service**
   - ✅ Доступен для Cart Service
   - ✅ Доступен для Payment Service
   - ❌ Блокирует внешний доступ

### Проверка работы RBAC

```bash
# Проверка активных политик
kubectl get authorizationpolicy -n e-commerce

# Тестирование разрешённого доступа
curl http://<INGRESS_IP>/api/products  # ✅ Должно работать
curl http://<INGRESS_IP>/api/cart/user123  # ✅ Должно работать

# Проверка блокировки прямого доступа (требует test pod)
kubectl run test-curl --image=curlimages/curl:latest -n e-commerce -- sleep 3600
kubectl exec -n e-commerce test-curl -- curl http://payment-service:5003/health
# ❌ Должно быть заблокировано (403 или timeout)
```

### Применение политик после изменений

**Важно:** После изменения политик авторизации необходимо перезапустить поды для применения новых правил:

```bash
# Перезапуск всех deployments для применения политик
kubectl rollout restart deployment -n e-commerce

# Ожидание готовности
kubectl rollout status deployment -n e-commerce
```

## Troubleshooting

### ⚠️ Важные изменения для OrbStack

#### Использование localhost:5001 registry
При использовании OrbStack необходимо тегировать и пушить образы в локальный registry:

```bash
# Тегирование образов для OrbStack
docker tag catalog-service:v1 localhost:5001/catalog-service:v1
docker push localhost:5001/catalog-service:v1

# В манифестах Kubernetes использовать:
image: localhost:5001/catalog-service:v1
imagePullPolicy: IfNotPresent
```

#### Проблема с readiness probes в Linkerd
Linkerd proxy может перехватывать health check запросы и отвечать HTTP/2 вместо HTTP/1.1, что приводит к ошибкам readiness probe (поды показывают 1/2 READY).

**Решение:** Добавить аннотацию для пропуска портов:
```yaml
metadata:
  annotations:
    config.linkerd.io/skip-inbound-ports: "5000"  # порт вашего сервиса
```

### ⚠️ Важные изменения в 2024

#### TrafficSplit API устарел
**Проблема:** При использовании устаревшего `split.smi-spec.io/v1alpha1` TrafficSplit в Linkerd могут возникать ошибки.

**Решение:** Используйте современные подходы:
- **Простой способ:** Разное количество реплик (`kubectl scale deployment`)
- **Точный способ:** HTTPRoute из Gateway API (Linkerd 2.18+)
- **Автоматический:** Flagger для канареечных развертываний

```bash
# Вместо TrafficSplit используйте:
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: payment-route
spec:
  parentRefs:
  - name: payment-service
  rules:
  - backendRefs:
    - name: payment-service-v1
      weight: 95
    - name: payment-service-v2
      weight: 5
EOF
```

### Типичные проблемы и их решение

#### 1. Ошибка 403 "rbac_access_denied"
**Симптомы:**
- Запросы возвращают ошибку 403
- В логах istio-proxy: `rbac_access_denied_matched_policy[none]`
- Сервисы не могут взаимодействовать друг с другом

**Диагностика:**
```bash
# Проверить логи Envoy proxy
kubectl logs deployment/api-gateway -n e-commerce -c istio-proxy

# Проверить AuthorizationPolicy
kubectl get authorizationpolicy -n e-commerce -o yaml
```

**Решение:**
```bash
# Исправить AuthorizationPolicy, добавив нужные service accounts
kubectl patch authorizationpolicy catalog-authz -n e-commerce --type='merge' -p='
spec:
  rules:
  - from:
    - source:
        principals: 
        - "cluster.local/ns/e-commerce/sa/default"    # API Gateway
        - "cluster.local/ns/e-commerce/sa/cart-service" # Cart Service
'
```

#### 2. Ошибка "Expecting value: line 1 column 1 (char 0)"
**Симптомы:**
- JSON parsing ошибки в Python сервисах
- Пустые ответы от upstream services

**Диагностика:**
```bash
# Проверить статус endpoints
istioctl proxy-config endpoint deployment/api-gateway -n e-commerce \
  --cluster "outbound|5001||catalog-service.e-commerce.svc.cluster.local"

# Проверить маршрутизацию
istioctl proxy-config route deployment/api-gateway -n e-commerce
```

**Причина:** 403/5xx ответы от upstream сервисов интерпретируются как пустой JSON

#### 3. mTLS конфигурация
**Симптомы:**
- 403 ошибки при включенном STRICT mTLS
- TLS handshake errors

**Решение:**
```bash
# Убедиться что все DestinationRule имеют tls.mode
kubectl get destinationrule -n e-commerce -o yaml | grep -A5 "tls:"

# Добавить mTLS конфигурацию если отсутствует
kubectl patch destinationrule catalog-dr -n e-commerce --type='merge' -p='
spec:
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
'
```

### Диагностические команды

```bash
# 1. Проверка общего статуса Service Mesh
istioctl check
kubectl get pods -n istio-system

# 2. Анализ конфигурации proxy
istioctl proxy-config route deployment/api-gateway -n e-commerce
istioctl proxy-config cluster deployment/api-gateway -n e-commerce
istioctl proxy-config endpoint deployment/api-gateway -n e-commerce

# 3. Проверка логов приложений и proxy
kubectl logs deployment/api-gateway -n e-commerce        # приложение
kubectl logs deployment/api-gateway -n e-commerce -c istio-proxy  # proxy

# 4. Проверка сертификатов и mTLS
istioctl authn tls-check catalog-service.e-commerce.svc.cluster.local

# 5. Анализ трафика в реальном времени (только Linkerd)
linkerd tap -n e-commerce deployment/api-gateway
```

### Полный процесс диагностики проблемы

1. **Воспроизвести проблему**
   ```bash
   kubectl port-forward -n e-commerce svc/api-gateway 8080:5000
   curl http://localhost:8080/api/products
   ```

2. **Проверить логи приложения**
   ```bash
   kubectl logs deployment/api-gateway -n e-commerce --tail=10
   ```

3. **Проверить логи Envoy proxy**
   ```bash
   kubectl logs deployment/api-gateway -n e-commerce -c istio-proxy --tail=10
   kubectl logs deployment/catalog-service -n e-commerce -c istio-proxy --tail=10
   ```

4. **Проверить конфигурацию маршрутизации**
   ```bash
   istioctl proxy-config route deployment/api-gateway -n e-commerce
   ```

5. **Проверить RBAC политики**
   ```bash
   kubectl get authorizationpolicy -n e-commerce
   ```

## Полезные команды

```bash
# Просмотр логов с Envoy proxy (Istio)
kubectl logs -n e-commerce <pod-name> -c istio-proxy

# Просмотр конфигурации Envoy
istioctl proxy-config cluster <pod-name> -n e-commerce

# Просмотр метрик Linkerd
linkerd stat -n e-commerce deploy

# Проверка трафика
linkerd tap -n e-commerce deploy/payment-service
```