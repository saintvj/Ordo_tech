require('dotenv').config();
const { createApp } = require('./app');

const PORT = parseInt(process.env.PORT, 10) || 8787;
const HOST = '127.0.0.1'; // Loopback only - never expose to public network
const MODEL = process.env.GEMINI_MODEL || 'gemini-3.5-flash-lite';

const app = createApp();

app.listen(PORT, HOST, () => {
  console.log(`=======================================================`);
  console.log(` Ordo Gemini Menu Scanner Proxy`);
  console.log(` Running on: http://${HOST}:${PORT}`);
  console.log(` Configured Model: ${MODEL}`);
  console.log(` Upstream Timeout: ${process.env.GEMINI_TIMEOUT_MS || 100000}ms`);
  console.log(` Max Retries: ${process.env.GEMINI_MAX_RETRIES || 3} attempts`);
  console.log(` API Key Status: ${process.env.GEMINI_API_KEY ? 'Configured' : 'MISSING (Set in .env)'}`);
  console.log(` Security: Strictly bound to local loopback (127.0.0.1)`);
  console.log(` Diagnostic Logging: Enabled`);
  console.log(`=======================================================`);
});

