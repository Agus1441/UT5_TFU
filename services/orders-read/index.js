import express from 'express';
import { Client as PgClient } from 'pg';
import fetch from 'node-fetch';
import { createClient as createRedis } from 'redis';

const app = express();
const READ_DB_URL = process.env.READ_DB_URL;
const CONFIG_URL = process.env.CONFIG_URL || 'http://config:8088/config';
const REDIS_URL = process.env.REDIS_URL || 'redis://redis:6379';

let config = { cacheTtlSec: 10 };
async function loadConfig() {
  try {
    const res = await fetch(CONFIG_URL);
    config = await res.json();
  } catch(e) { console.error('[config] load error', e.message); }
}
setInterval(loadConfig, 30000);
await loadConfig();

const rdb = new PgClient({ connectionString: READ_DB_URL });
await rdb.connect();
await rdb.query(`CREATE TABLE IF NOT EXISTS orders_read(
  id TEXT PRIMARY KEY, status TEXT, amount NUMERIC
)`);

const redis = createRedis({ url: REDIS_URL });
redis.on('error', err => console.error('redis error', err));
await redis.connect();

app.get('/health', (req,res)=> res.json({status:'UP', ts:Date.now()}));

app.get('/orders/:id', async (req,res)=>{
  const id = req.params.id;
  const cacheKey = `order:${id}`;
  const cached = await redis.get(cacheKey);
  if (cached) return res.json(JSON.parse(cached));
  const q = await rdb.query('SELECT id,status,amount FROM orders_read WHERE id=$1',[id]);
  if (!q.rows.length) return res.status(404).json({error:'not_found'});
  const data = q.rows[0];
  await redis.set(cacheKey, JSON.stringify(data), { EX: config.cacheTtlSec || 10 });
  res.json(data);
});

app.listen(3001, ()=> console.log('orders-read on :3001'));
