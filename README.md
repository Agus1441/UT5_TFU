# UT4_TFU Demo — Orders API (Patrones: Disponibilidad, Rendimiento, Seguridad, Despliegue)

Este proyecto *listo para correr* demuestra:
- **Disponibilidad**: Circuit Breaker (orders-write ↔ payments-adapter) + Health Endpoint Monitoring.
- **Rendimiento**: Queue-Based Load Leveling (RabbitMQ) + CQRS con Materialized View (projector → Postgres read DB).
- **Seguridad**: Gatekeeper (Kong) con OIDC simulado y rate limiting.
- **Facilidad de modificación**: External Configuration Store (infra/config-store).

## Requisitos
- Docker + Docker Compose
- (Opcional) Make, curl

## Arranque rápido
```bash
docker compose up -d --build
# Gateway: http://localhost:8080
# Keycloak (dummy): http://localhost:8081
# RabbitMQ: http://localhost:15672 (guest/guest)
```

## Endpoints útiles
- Gateway health: `curl http://localhost:8080/health`
- Crear orden: `curl -H "Authorization: Bearer demo" -H "Content-Type: application/json" -d '{"items":[{"sku":"A","qty":1}]}' http://localhost:8080/orders`
- Pagar orden: `curl -H "Authorization: Bearer demo" -H "Content-Type: application/json" -X POST http://localhost:8080/orders/123/pay -d '{"amount":15}'`
- Consultar orden: `curl -H "Authorization: Bearer demo" http://localhost:8080/orders/123`

## Estructura
- `services/` Node.js microservicios (Express).
- `infra/config-store/` Config externa simple (JSON), consumida por servicios.
- `deploy/gateway/kong.yml` Kong declarativo con OIDC simulado + rate limiting.
- `docs/` PDF con la entrega
- `tests/` scripts de carga, disponibilidad y seguridad.
