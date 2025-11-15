import express from 'express';
import axios from 'axios';
import amqp from 'amqplib';
import fetch from 'node-fetch';
import CircuitBreaker from 'opossum';
import { Client as PgClient } from 'pg';

const app = express();
app.use(express.json());

const CONFIG_URL = process.env.CONFIG_URL || 'http://config:8088/config';
const QUEUE_URL = process.env.QUEUE_URL || 'amqp://guest:guest@queue:5672/';
const WRITE_DB_URL = process.env.WRITE_DB_URL;
const READ_DB_URL = process.env.READ_DB_URL;
const PAYMENTS_URL = process.env.PAYMENTS_URL || 'http://payments-adapter:3002';
const CB_ERROR_THRESHOLD = parseInt(process.env.CB_ERROR_THRESHOLD || '5',10);
const CB_TIMEOUT_MS = parseInt(process.env.CB_TIMEOUT_MS || '10000',10);

let config = { paymentMaxRetries: 3 };
async function loadConfig() {
  try {
    const res = await fetch(CONFIG_URL);
    config = await res.json();
    console.log('[config] loaded', config);
  } catch(e) { console.error('[config] load error', e.message); }
}
setInterval(loadConfig, 30000);
await loadConfig();

// DB init (write)
const wdb = new PgClient({ connectionString: WRITE_DB_URL });
await wdb.connect();
await wdb.query(`CREATE TABLE IF NOT EXISTS orders_write(
  id TEXT PRIMARY KEY, status TEXT, amount NUMERIC
)`);

// producer (events)
const amqpConn = await amqp.connect(QUEUE_URL);
const ch = await amqpConn.createChannel();
await ch.assertQueue('payments', { durable: false });
await ch.assertQueue('projector', { durable: false });

// Circuit breaker to payments
async function chargePayment(payload) {
  const res = await axios.post(PAYMENTS_URL + '/charge', payload, { timeout: 5000 });
  return res.data;
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

// Routes
app.get('/health', (req,res)=> res.json({status:'UP', ts:Date.now()}));

app.post('/orders', async (req,res)=>{
  const id = String(Date.now());
  await wdb.query('INSERT INTO orders_write(id,status,amount) VALUES($1,$2,$3)',
    [id, 'CREATED', 0]);
  ch.sendToQueue('projector', Buffer.from(JSON.stringify({type:'OrderCreated', id})));
  res.status(201).json({id, status:'CREATED'});
});

app.post('/orders/:id/pay', async (req,res)=>{
  const id = req.params.id;
  const amount = Number((req.body && req.body.amount) || 10);
  let attempt = 0;
  const maxRetries = config.paymentMaxRetries ?? 3;
  try {
    const execCharge = () => breaker.fire({ id, amount });
    while (true) {
      try {
        await execCharge();
        break;
      } catch (e) {
        attempt++;
        if (attempt > maxRetries || breaker.opened) throw e;
        await new Promise(r=>setTimeout(r, 200 * attempt));
      }
    }
    await wdb.query('UPDATE orders_write SET status=$2, amount=$3 WHERE id=$1',
      [id, 'PAID', amount]);
    ch.sendToQueue('payments', Buffer.from(JSON.stringify({type:'PaymentRequested', id, amount})));
    ch.sendToQueue('projector', Buffer.from(JSON.stringify({type:'PaymentCompleted', id, amount})));
    res.json({id, status:'PAID'});
  } catch (e) {
    res.status(503).json({error:'payment_failed_or_cb_open', details: e.message});
  }
});

app.listen(3000, ()=> console.log('orders-write on :3000'));
