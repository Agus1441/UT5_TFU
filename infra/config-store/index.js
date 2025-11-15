import express from 'express';
import fs from 'fs';

const app = express();
app.use(express.json());
const file = './config.json';

function readConfig() {
  try { return JSON.parse(fs.readFileSync(file,'utf8')); }
  catch { return { paymentMaxRetries: 3, cacheTtlSec: 10 }; }
}

app.get('/config', (req,res)=> res.json(readConfig()));
app.post('/config', (req,res)=> {
  fs.writeFileSync(file, JSON.stringify(req.body||{}, null, 2));
  res.json({ok:true});
});

app.listen(8088, ()=> console.log('config-store on :8088'));
