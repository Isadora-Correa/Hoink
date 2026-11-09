// Entrada da API na Vercel (função serverless). Usa o build do tsup (dist/app.js), então a Vercel não
// precisa compilar o TypeScript. Os agendamentos do server.ts são substituídos pelo cron do vercel.json.
import { createApp } from '../dist/app.js';

export default createApp();
