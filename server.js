const fs = require('fs');
const path = require('path');
const express = require('express');
const { Pool } = require('pg');
const { execFile } = require('child_process');
const { promisify } = require('util');

function loadDotEnv(dotEnvPath) {
  if (!fs.existsSync(dotEnvPath)) {
    return;
  }
  const content = fs.readFileSync(dotEnvPath, 'utf8');
  const lines = content.split(/\r?\n/);
  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) {
      continue;
    }
    const normalized = line.startsWith('export ') ? line.slice(7).trim() : line;
    const eqIdx = normalized.indexOf('=');
    if (eqIdx <= 0) {
      continue;
    }
    const key = normalized.slice(0, eqIdx).trim();
    let value = normalized.slice(eqIdx + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (key && process.env[key] === undefined) {
      process.env[key] = value;
    }
  }
}

function envFlag(name, defaultValue) {
  const raw = process.env[name];
  if (raw === undefined || raw === '') {
    return defaultValue;
  }
  return !['0', 'false', 'no', 'off'].includes(raw.trim().toLowerCase());
}

function buildDbConfig() {
  const sslMode = process.env.DB_SSLMODE || process.env.PGSSLMODE || 'disable';
  const ssl = sslMode === 'disable' ? false : { rejectUnauthorized: sslMode !== 'no-verify' };

  if (process.env.DATABASE_URL) {
    return {
      connectionString: process.env.DATABASE_URL,
      ssl,
    };
  }

  return {
    host: process.env.DB_HOST || 'localhost',
    port: Number.parseInt(process.env.DB_PORT || '5432', 10),
    database: process.env.DB_NAME || process.env.POSTGRES_DB || 'vulnerableapp',
    user: process.env.DB_USER || process.env.POSTGRES_USER || 'vulnerableapp',
    password: process.env.DB_PASSWORD || process.env.POSTGRES_PASSWORD || '',
    ssl,
  };
}

loadDotEnv(path.join(__dirname, '.env'));

const app = express();
const PORT = process.env.PORT || 3000;
const HOST = process.env.HOST || '0.0.0.0';
const INIT_DB_ON_START = envFlag('DB_INIT_ON_START', true);
const MAX_ASSISTANT_INPUT_LENGTH = Number.parseInt(
  process.env.ASSISTANT_MAX_INPUT_LENGTH || '10000',
  10
);
const execFileAsync = promisify(execFile);
const pool = new Pool(buildDbConfig());

async function initializeDatabase() {
  if (!INIT_DB_ON_START) {
    return;
  }

  const schemaPath = path.join(__dirname, 'db', 'schema.sql');
  const seedPath = path.join(__dirname, 'db', 'seed.sql');
  const schemaSQL = fs.readFileSync(schemaPath, 'utf8');
  const seedSQL = fs.readFileSync(seedPath, 'utf8');
  const client = await pool.connect();

  try {
    await client.query('BEGIN');
    await client.query(schemaSQL);
    await client.query(seedSQL);
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function checkDatabaseReady() {
  await pool.query('SELECT 1');
}

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

app.get('/healthz', (_req, res) => {
  res.json({ status: 'ok' });
});

app.get('/readyz', async (_req, res) => {
  try {
    await checkDatabaseReady();
    return res.json({ status: 'ready' });
  } catch (error) {
    return res.status(503).json({
      status: 'not-ready',
      error: error.message,
    });
  }
});

app.get(['/7zip.html', '/zip.html'], (_req, res) => {
  res.sendFile(path.join(__dirname, '7zip.html'));
});

// Intentionally vulnerable lab endpoint.
// Demonstrates SQL injection by concatenating untrusted input into SQL.
// Never use this pattern in production.
app.get('/api/clients', async (req, res) => {
  const q = String(req.query.q || '').trim();
  const sql =
    "SELECT id, name, country_of_birth FROM clients " +
    "WHERE name ILIKE '%" +
    q +
    "%' OR country_of_birth ILIKE '%" +
    q +
    "%' " +
    'ORDER BY id';

  try {
    const result = await pool.query(sql);
    return res.json({
      mode: 'lab-vulnerable',
      warning: 'Intentionally vulnerable endpoint. Fake data only.',
      sql,
      clients: result.rows,
    });
  } catch (error) {
    return res.status(400).json({
      mode: 'lab-vulnerable',
      warning: 'Intentionally vulnerable endpoint. Fake data only.',
      sql,
      error: error.message,
    });
  }
});

app.get('/api/me/records', async (req, res) => {
  const q = String(req.query.q || 'Alice').trim();
  const sql =
    "SELECT id, name, country_of_birth FROM clients " +
    "WHERE name ILIKE '%" +
    q +
    "%' " +
    'ORDER BY id';

  try {
    const result = await pool.query(sql);
    return res.json({
      mode: 'lab-vulnerable',
      warning: 'Intentionally vulnerable endpoint. Fake data only.',
      sql,
      clients: result.rows,
    });
  } catch (error) {
    return res.status(400).json({
      mode: 'lab-vulnerable',
      warning: 'Intentionally vulnerable endpoint. Fake data only.',
      sql,
      error: error.message,
    });
  }
});

function extractAssistantAnswer(stdoutText) {
  const marker = '=== Assistant Answer ===';
  const idx = stdoutText.indexOf(marker);
  if (idx === -1) {
    return stdoutText.trim();
  }

  const after = stdoutText.slice(idx + marker.length).trim();
  const sqlMarker = '\n=== SQL ';
  const sqlIdx = after.indexOf(sqlMarker);
  if (sqlIdx === -1) {
    return after.trim();
  }
  return after.slice(0, sqlIdx).trim();
}

app.post('/api/assistant/chat', async (req, res) => {
  const question = String((req.body && req.body.question) || '').trim();
  if (!question) {
    return res.status(400).json({ error: 'Question is required.' });
  }
  if (question.length > MAX_ASSISTANT_INPUT_LENGTH) {
    return res.status(400).json({ error: 'Question is too long.' });
  }

  const scriptPath = path.join(__dirname, 'personal_ai_assistant.py');
  const args = [scriptPath, question];

  try {
    const { stdout, stderr } = await execFileAsync('python3', args, {
      cwd: __dirname,
      env: process.env,
      timeout: 120000,
      maxBuffer: 1024 * 1024,
    });

    if (stdout) {
      console.log('\n=== Assistant Raw STDOUT ===\n' + stdout);
    }
    if (stderr) {
      console.error('\n=== Assistant Raw STDERR ===\n' + stderr);
    }

    const answer = extractAssistantAnswer(stdout || '');
    return res.json({
      answer,
      raw_output: stdout || '',
      stderr: stderr || '',
    });
  } catch (error) {
    return res.status(500).json({
      error: 'Assistant execution failed.',
      details: error.stderr || error.message || String(error),
    });
  }
});

async function start() {
  try {
    await initializeDatabase();
    const server = app.listen(PORT, HOST, () => {
      console.log(`Demo server running at http://${HOST}:${PORT}`);
      console.log('Using fake data only. Do not use in production.');
    });

    const shutdown = async () => {
      console.log('Shutting down server...');
      server.close(async () => {
        await pool.end();
        process.exit(0);
      });
    };

    process.on('SIGINT', shutdown);
    process.on('SIGTERM', shutdown);
  } catch (error) {
    console.error('Failed to start server:', error);
    await pool.end();
    process.exit(1);
  }
}

start();
