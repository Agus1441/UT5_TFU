# Monolith - Orders API

Versión monolítica consolidada del sistema de órdenes.

## Características

- **Arquitectura monolítica**: Todos los servicios consolidados en una sola aplicación
- **Base de datos única**: Una sola instancia PostgreSQL para lectura y escritura
- **Comunicación síncrona**: Sin mensajería asíncrona, todo es síncrono
- **Autenticación integrada**: Middleware de Express para autenticación
- **Rate limiting integrado**: Middleware de Express para limitación de tasa
- **Cache opcional**: Redis (si está disponible) o caché en memoria

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

## Diferencias con la versión de microservicios

- ✅ Un solo proceso en lugar de 4 servicios
- ✅ Una sola base de datos en lugar de read/write separadas
- ✅ Sin RabbitMQ (comunicación síncrona directa)
- ✅ Sin API Gateway (middleware integrado)
- ✅ Sin config-store como servicio (archivo local)
- ✅ Proyección síncrona en lugar de asíncrona
- ✅ Redis opcional (fallback a caché en memoria)

