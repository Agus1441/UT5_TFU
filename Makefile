
# UT4_TFU Demo Makefile — Diego style
# Use: make help

# Config overridables
ENDPOINT ?= http://localhost:8080
APIKEY   ?= demo
ORDERS   ?= 200
AMOUNT   ?= 150

COMPOSE_BASE := docker-compose -f docker-compose.yml

# -------- Core lifecycle --------
.PHONY: help
help:
	@echo ""
	@echo "UT4_TFU Demo — Make targets"
	@echo "  make up             # docker-compose up (base)"
	@echo "  make up-mac         # docker-compose up using mac override"
	@echo "  make down           # stop & remove containers/volumes"
	@echo "  make ps             # show running services"
	@echo "  make logs           # tail gateway + services logs"
	@echo ""
	@echo "  make demo-availability  # Health + CB controlled failure demo"
	@echo "  make demo-performance   # Burst payments (Queue + CQRS + Cache)"
	@echo "  make demo-security      # API key + Rate Limiting"
	@echo "  make demo-config        # External Config hot change"
	@echo ""
	@echo "  make cb-open            # Set failure rate to 100% (open breaker)"
	@echo "  make cb-close           # Set failure rate to 0% (close breaker)"
	@echo "  make config-show        # Show current config JSON"
	@echo "  make config-set         # Set paymentMaxRetries=1, cacheTtlSec=3"
	@echo "  make seed-order         # Create one order (returns ID)"
	@echo "  make pay ID=123         # Pay order ID=$(ID)"
	@echo "  make get ID=123         # Get order ID=$(ID)"
	@echo ""

.PHONY: up
up:
	$(COMPOSE_BASE) up -d --build

.PHONY: up-mac
up-mac:
	docker-compose -f docker-compose.yml -f docker-compose.mac.yml up -d --build

.PHONY: down
down:
	docker-compose down -v

.PHONY: ps
ps:
	docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

.PHONY: logs
logs:
	@echo "Tailing logs (Ctrl+C to stop)"
	@docker-compose logs -f --tail=50

# -------- Demo flows --------

.PHONY: demo-availability
demo-availability:
	@ENDPOINT=$(ENDPOINT) APIKEY=$(APIKEY) bash tests/availability/health_smoke.sh
	@echo ""
	@echo "==> Open breaker by forcing failures (rate=1.0)"; \
	curl -s -X POST "http://localhost:3002/toggle?rate=1.0" | sed 's/^/   /'
	@echo ""
	@echo "==> Try several payments to show 503 fast-fail"
	@for i in $$(seq 1 10); do \
	  code=$$(curl -s -o /dev/null -w "%{http_code} " \
	    -H "apikey: $(APIKEY)" -H "Content-Type: application/json" \
	    -X POST $(ENDPOINT)/orders/$$((2000+i))/pay --data '{"amount":5}'); \
	  printf "$$code "; \
	done; echo ""
	@echo ""
	@echo "==> Close breaker (rate=0.0)"; \
	curl -s -X POST "http://localhost:3002/toggle?rate=0.0" | sed 's/^/   /'
	@echo "Done."

.PHONY: demo-performance
demo-performance:
	@ENDPOINT=$(ENDPOINT) APIKEY=$(APIKEY) ORDERS=$(ORDERS) AMOUNT=$(AMOUNT) bash tests/load/burst_payments.sh
	@echo ""
	@echo "==> Query same order twice to show cache speedup"
	@time curl -s -H "apikey: $(APIKEY)" $(ENDPOINT)/orders/123 >/dev/null || true
	@time curl -s -H "apikey: $(APIKEY)" $(ENDPOINT)/orders/123 >/dev/null || true
	@echo "Open RabbitMQ UI -> http://localhost:15672"

.PHONY: demo-security
demo-security:
	@ENDPOINT=$(ENDPOINT) APIKEY=$(APIKEY) bash tests/security/auth_and_rl.sh

.PHONY: demo-config
demo-config:
	@echo "Current config:"
	@curl -s http://localhost:8088/config | python3 -m json.tool || curl -s http://localhost:8088/config
	@echo ""
	@echo "Setting paymentMaxRetries=1, cacheTtlSec=3"
	@curl -s -X POST http://localhost:8088/config -H "Content-Type: application/json" \
		--data '{"paymentMaxRetries":1,"cacheTtlSec":3}' | sed 's/^/  /'
	@echo ""
	@echo "New config:"
	@curl -s http://localhost:8088/config | python3 -m json.tool || curl -s http://localhost:8088/config

# -------- Utilities --------

.PHONY: cb-open
cb-open:
	@echo "Force integration failures (rate=1.0)..."
	@docker-compose exec orders-write sh -lc \
		'wget -qO- --post-data="{}" "http://payments-adapter:3002/toggle?rate=1.0"' | sed 's/^/  /'

.PHONY: cb-close
cb-close:
	@echo "Restore integration (rate=0.0)..."
	@docker-compose exec orders-write sh -lc \
		'wget -qO- --post-data="{}" "http://payments-adapter:3002/toggle?rate=0.0"' | sed 's/^/  /'

.PHONY: config-show
config-show:
	curl -s http://localhost:8088/config | python3 -m json.tool || curl -s http://localhost:8088/config

.PHONY: config-set
config-set:
	curl -s -X POST http://localhost:8088/config -H "Content-Type: application/json" \
		--data '{"paymentMaxRetries":1,"cacheTtlSec":3}' | sed 's/^/  /'


.PHONY: seed-order
seed-order:
	@curl -s -H "apikey: $(APIKEY)" -H "Content-Type: application/json" \
	  -d '{"items":[{"sku":"A","qty":1}]}' $(ENDPOINT)/orders | python3 -m json.tool || true

.PHONY: pay
pay:
	@test -n "$(ID)" || (echo "Usage: make pay ID=123"; exit 1)
	@curl -s -H "apikey: $(APIKEY)" -H "Content-Type: application/json" \
	  -X POST $(ENDPOINT)/orders/$(ID)/pay --data '{"amount": $(AMOUNT)}' | python3 -m json.tool || true

.PHONY: get
get:
	@test -n "$(ID)" || (echo "Usage: make get ID=123"; exit 1)
	@curl -s -H "apikey: $(APIKEY)" $(ENDPOINT)/orders/$(ID) | python3 -m json.tool || true
