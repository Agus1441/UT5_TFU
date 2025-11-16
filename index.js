// index.js
import express from 'express';
import amqp from 'amqplib';
import { Client as PgClient } from 'pg';
import { createClient as createRedis } from 'redis';
import CircuitBreaker from 'opossum';

const app = express();

// env (solo lo que pasaste en docker-compose)
const DATABASE_URL = process.env.DATABASE_URL;
const REDIS_URL = process.env.REDIS_URL || 'redis://redis:6379';
const QUEUE_URL = process.env.QUEUE_URL || 'amqp://guest:guest@queue:5672/';
let FAILURE_RATE = parseFloat(process.env.FAILURE_RATE || '0.3');
const CB_ERROR_THRESHOLD = parseInt(process.env.CB_ERROR_THRESHOLD || '5', 10);
const CB_TIMEOUT_MS = parseInt(process.env.CB_TIMEOUT_MS || '10000', 10);

app.use(express.text({ type: ['text/xml', 'application/soap+xml', 'application/xml'] }));
app.use(express.json());

function buildSoapFault(code, message) {
  return `
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
      <soap:Body>
        <soap:Fault>
          <faultcode>${code}</faultcode>
          <faultstring>${message}</faultstring>
        </soap:Fault>
      </soap:Body>
    </soap:Envelope>
  `.trim();
}

function buildGetOrderResponse(id, status, amount) {
  return `
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
      <soap:Body>
        <GetOrderResponse>
          <order>
            <id>${id}</id>
            <status>${status}</status>
            <amount>${amount}</amount>
          </order>
        </GetOrderResponse>
      </soap:Body>
    </soap:Envelope>
  `.trim();
}

(async () => {
  // DB (write + read en la misma URL)
  const db = new PgClient({ connectionString: DATABASE_URL });
  await db.connect();
  await db.query(`CREATE TABLE IF NOT EXISTS orders_write(
    id TEXT PRIMARY KEY, status TEXT, amount NUMERIC
  )`);
  await db.query(`CREATE TABLE IF NOT EXISTS orders_read(
    id TEXT PRIMARY KEY, status TEXT, amount NUMERIC
  )`);

  // Redis
  const redis = createRedis({ url: REDIS_URL });
  redis.on('error', err => console.error('redis error', err));
  await redis.connect();

  // RabbitMQ
  const conn = await amqp.connect(QUEUE_URL);
  const ch = await conn.createChannel();
  await ch.assertQueue('projector', { durable: false });
  await ch.assertQueue('payments', { durable: false });

  // projector -> orders_read
  await ch.consume('projector', async msg => {
    if (!msg) return;
    try {
      const evt = JSON.parse(msg.content.toString());
      if (evt.type === 'OrderCreated') {
        await db.query(
          'INSERT INTO orders_read(id,status,amount) VALUES($1,$2,$3) ON CONFLICT (id) DO NOTHING',
          [evt.id, 'CREATED', 0]
        );
      } else if (evt.type === 'PaymentCompleted') {
        await db.query(
          'INSERT INTO orders_read(id,status,amount) VALUES($1,$2,$3) ON CONFLICT (id) DO UPDATE SET status=EXCLUDED.status, amount=EXCLUDED.amount',
          [evt.id, 'PAID', evt.amount || 0]
        );
      }
      ch.ack(msg);
    } catch (e) {
      console.error('projector error', e);
      ch.ack(msg);
    }
  });
  console.log('projector running');

  // consumer payments
  await ch.consume('payments', msg => {
    if (!msg) return;
    const m = JSON.parse(msg.content.toString());
    console.log('[payments-consumer] processing', m);
    setTimeout(() => ch.ack(msg), 50);
  });

  // función interna de cobro (antes /charge del payments-adapter)
  async function internalCharge() {
    if (Math.random() < FAILURE_RATE) {
      const err = new Error('random_fail');
      throw err;
    }
    return { status: 'CHARGED' };
  }

  // circuit breaker
  async function chargePayment(payload) {
    // payload no se usa, pero lo dejamos igual que antes
    return internalCharge();
  }

  const breaker = new CircuitBreaker(chargePayment, {
    errorThresholdPercentage: 50,
    timeout: 5000,
    volumeThreshold: CB_ERROR_THRESHOLD,
    resetTimeout: CB_TIMEOUT_MS
  });

  breaker.on('open', () => console.warn('[cb] OPEN'));
  breaker.on('halfOpen', () => console.warn('[cb] HALF-OPEN'));
  breaker.on('close', () => console.warn('[cb] CLOSE'));

  // ---------- endpoints de payments (lo que tenías en payments-adapter) ----------
  app.get('/health', (req, res) =>
    res.json({ status: 'UP', failureRate: FAILURE_RATE, ts: Date.now() })
  );

  app.post('/toggle', (req, res) => {
    const p = Number(req.query.rate);
    if (!isNaN(p) && p >= 0 && p <= 1) FAILURE_RATE = p;
    res.json({ failureRate: FAILURE_RATE });
  });

  app.post('/charge', async (req, res) => {
    try {
      const r = await internalCharge();
      res.json(r);
    } catch (e) {
      res.status(500).json({ error: 'random_fail' });
    }
  });

  // ---------- endpoints de orders-write ----------
  app.post('/orders', async (req, res) => {
    const id = String(Date.now());
    await db.query(
      'INSERT INTO orders_write(id,status,amount) VALUES($1,$2,$3)',
      [id, 'CREATED', 0]
    );
    ch.sendToQueue('projector', Buffer.from(JSON.stringify({ type: 'OrderCreated', id })));
    res.status(201).json({ id, status: 'CREATED' });
  });

  app.post('/orders/:id/pay', async (req, res) => {
    const id = req.params.id;
    const amount = Number((req.body && req.body.amount) || 10);
    let attempt = 0;
    const maxRetries = 3;

    try {
      const execCharge = () => breaker.fire({ id, amount });
      while (true) {
        try {
          await execCharge();
          break;
        } catch (e) {
          attempt++;
          if (attempt > maxRetries || breaker.opened) throw e;
          await new Promise(r => setTimeout(r, 200 * attempt));
        }
      }

      await db.query(
        'UPDATE orders_write SET status=$2, amount=$3 WHERE id=$1',
        [id, 'PAID', amount]
      );
      ch.sendToQueue('payments', Buffer.from(JSON.stringify({ type: 'PaymentRequested', id, amount })));
      ch.sendToQueue('projector', Buffer.from(JSON.stringify({ type: 'PaymentCompleted', id, amount })));
      res.json({ id, status: 'PAID' });
    } catch (e) {
      res.status(503).json({ error: 'payment_failed_or_cb_open', details: e.message });
    }
  });

  // ---------- endpoints de orders-read (REST + SOAP) ----------
  app.get('/orders/:id', async (req, res) => {
    const id = req.params.id;
    const cacheKey = `order:${id}`;
    const cached = await redis.get(cacheKey);
    if (cached) return res.json(JSON.parse(cached));

    const q = await db.query(
      'SELECT id,status,amount FROM orders_read WHERE id=$1',
      [id]
    );
    if (!q.rows.length) return res.status(404).json({ error: 'not_found' });
    const data = q.rows[0];
    await redis.set(cacheKey, JSON.stringify(data), { EX: 10 });
    res.json(data);
  });

  app.post('/soap/order', async (req, res) => {
    try {
      const xml = req.body;
      const idMatch = xml.match(/<id>([^<]+)<\/id>/);
      if (!idMatch) {
        res.status(400);
        return res.send(buildSoapFault('Client', 'Missing <id> in request'));
      }
      const id = idMatch[1];

      const cacheKey = `order:${id}`;
      let order = null;

      const cached = await redis.get(cacheKey);
      if (cached) {
        order = JSON.parse(cached);
      } else {
        const q = await db.query(
          'SELECT id,status,amount FROM orders_read WHERE id=$1',
          [id]
        );
        if (!q.rows.length) {
          res.status(404);
          return res.send(buildSoapFault('Client', `Order ${id} not found`));
        }
        order = q.rows[0];
        await redis.set(cacheKey, JSON.stringify(order), { EX: 10 });
      }

      const soapResponse = buildGetOrderResponse(order.id, order.status, order.amount);
      res.set('Content-Type', 'text/xml');
      return res.send(soapResponse);
    } catch (err) {
      res.status(500);
      return res.send(buildSoapFault('Server', 'Internal server error'));
    }
  });

  // ---------- start ----------
  app.listen(3000, () => console.log('monolith on :3000'));
})().catch(e => {
  console.error('monolith startup error', e);
  process.exit(1);
});
