import amqp from 'amqplib';
import { Client as PgClient } from 'pg';

const rdb = new PgClient({ connectionString: process.env.READ_DB_URL });
await rdb.connect();
await rdb.query(`CREATE TABLE IF NOT EXISTS orders_read(
  id TEXT PRIMARY KEY, status TEXT, amount NUMERIC
)`);

(async ()=>{
  const conn = await amqp.connect(process.env.QUEUE_URL || 'amqp://guest:guest@queue:5672/');
  const ch = await conn.createChannel();
  await ch.assertQueue('projector', { durable: false });
  await ch.consume('projector', async msg => {
    const evt = JSON.parse(msg.content.toString());
    if (evt.type === 'OrderCreated') {
      await rdb.query('INSERT INTO orders_read(id,status,amount) VALUES($1,$2,$3) ON CONFLICT (id) DO NOTHING',
        [evt.id, 'CREATED', 0]);
    } else if (evt.type === 'PaymentCompleted') {
      await rdb.query('INSERT INTO orders_read(id,status,amount) VALUES($1,$2,$3) ON CONFLICT (id) DO UPDATE SET status=EXCLUDED.status, amount=EXCLUDED.amount',
        [evt.id, 'PAID', evt.amount || 0]);
    }
    ch.ack(msg);
  });
  console.log('projector running');
})().catch(e=> console.error('projector error', e));
