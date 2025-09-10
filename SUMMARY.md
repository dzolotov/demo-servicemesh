# Service Mesh Demo - Краткое описание

## Обзор проекта

Демонстрационное приложение e-commerce для изучения возможностей Service Mesh архитектур (Istio и Linkerd).

## Архитектура приложения

### Микросервисы:
- **Gateway** - входная точка, маршрутизация запросов
- **Catalog** - каталог товаров
- **Cart** - корзина покупателя (использует Redis)
- **Payment** - обработка платежей
- **Redis** - хранилище данных корзины

## Основные демонстрации

### 1. Развертывание с Istio
- Автоматическое внедрение sidecar-контейнеров
- Настройка Gateway и VirtualService
- Политики авторизации (RBAC)
- Mutual TLS между сервисами
- Наблюдаемость через Kiali
- Метрики в Grafana/Prometheus

### 2. Развертывание с Linkerd
- Установка control plane
- Внедрение прокси через аннотации
- Service Profiles для маршрутизации
- Политики безопасности
- Визуализация через Linkerd Dashboard
- Золотые метрики (latency, traffic, errors)

### 3. Тестирование отказоустойчивости
- Chaos Engineering сценарии
- Внедрение задержек и ошибок
- Circuit Breaker паттерны
- Retry и Timeout политики
- Канареечные развертывания

## Ключевые возможности

### Безопасность
- mTLS шифрование трафика
- RBAC авторизация
- Сегментация сети
- Изоляция namespace

### Наблюдаемость
- Распределенная трассировка
- Метрики производительности
- Логирование запросов
- Визуализация топологии

### Управление трафиком
- A/B тестирование
- Канареечные релизы
- Балансировка нагрузки
- Rate limiting

## Быстрый старт

### Локальное тестирование (Docker Compose):
```bash
./test-local.sh
```

### Развертывание в Kubernetes с Istio:
```bash
./deploy-istio.sh
./test-demo.sh
```

### Развертывание в Kubernetes с Linkerd:
```bash
./deploy-linkerd.sh
./quick-test.sh
```

## Структура проекта

```
e-commerce-demo/
├── services/          # Исходный код микросервисов
├── kubernetes/        # Манифесты Kubernetes
├── istio/            # Конфигурации Istio
├── linkerd/          # Конфигурации Linkerd
├── monitoring/       # Настройки мониторинга
├── deploy-*.sh       # Скрипты развертывания
└── test-*.sh         # Скрипты тестирования
```

## Требования

- Kubernetes 1.28+
- kubectl
- Docker
- Minikube (для локального тестирования)
- 8GB RAM минимум
- 20GB свободного места на диске

## Полезные команды

### Просмотр логов:
```bash
kubectl logs -n e-commerce -l app=gateway --tail=100
```

### Мониторинг метрик:
```bash
# Istio
istioctl dashboard kiali

# Linkerd
linkerd viz dashboard
```

### Очистка ресурсов:
```bash
./uninstall-istio.sh
# или
./uninstall-linkerd.sh
```