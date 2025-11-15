import express from 'express';
import amqp from 'amqplib';

const app = express();
app.use(express.json());
let FAILURE_RATE = parseFloat(process.env.FAILURE_RATE || '0.3');

app.get('/health', (req,res)=> res.json({status:'UP', failureRate: FAILURE_RATE}));
app.post('/toggle', (req,res)=> {
  const p = Number(req.query.rate);
  if (!isNaN(p) && p>=0 && p<=1) FAILURE_RATE = p;
  res.json({failureRate: FAILURE_RATE});
});

app.post('/charge', (req,res)=>{
  // synchronous style charge for CB demo
  if (Math.random() < FAILURE_RATE) {
    return res.status(500).json({error:'random_fail'});
  }
  res.json({status:'CHARGED'});
});

// Consumer (competing) for 'payments' queue (background)
(async ()=>{
  try {
    const conn = await amqp.connect(process.env.QUEUE_URL || 'amqp://queue');
    const ch = await conn.createChannel();
    await ch.assertQueue('payments', { durable: false });
    await ch.consume('payments', msg => {
      const m = JSON.parse(msg.content.toString());
      console.log('[payments-consumer] processing', m);
      setTimeout(()=> ch.ack(msg), 50);
    });
  } catch(e) {
    console.error('amqp error', e);
  }
})();

app.listen(3002, ()=> console.log('payments-adapter on :3002'));
