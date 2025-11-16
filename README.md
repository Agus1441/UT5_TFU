# Monolith - Orders API

Versión monolítica consolidada del sistema de órdenes.

## Características

- **Arquitectura monolítica**: Todos los servicios consolidados en una sola aplicación
- **Base de datos única**: Una sola instancia PostgreSQL para lectura y escritura

## Requisitos

- Docker + Docker Compose

## Arranque

```bash
docker compose up -d --build
```

## Endpoints

- **Health**: `GET http://localhost:3000/health`
- **Crear orden**: 
  ```bash
  curl -H "Authorization: Bearer demo" \
       -H "Content-Type: application/json" \
       -X POST http://localhost:3000/orders
  ```
- **Pagar orden**: 
  ```bash
  curl -H "Authorization: Bearer demo" \
       -H "Content-Type: application/json" \
       -X POST http://localhost:3000/orders/123/pay \
       -d '{"amount":15}'
  ```
- **Consultar orden**: 
  ```bash
  curl -H "Authorization: Bearer demo" \
       http://localhost:3000/orders/123
  ```
- **SOAP endpoint**: 
  ```bash
  curl -H "Authorization: Bearer demo" \
       -H "Content-Type: text/xml" \
       -X POST http://localhost:3000/soap/order \
       -d '<soap:Envelope><soap:Body><id>123</id></soap:Body></soap:Envelope>'
  ```

## Configuración

La configuración se lee desde `config.json`:
- `paymentMaxRetries`: Número máximo de reintentos para pagos (default: 3)
- `cacheTtlSec`: TTL del caché en segundos (default: 10)


