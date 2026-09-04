require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
const {
  decodeNameParam,
  installAsyncRouteWrapper,
  parsePositiveInt,
} = require('./route_utils');

const app = express();
const pool = new Pool({ connectionString: process.env.DATABASE_URL });

pool.on('error', (err) => {
  console.error('Unexpected database pool error:', err);
});

process.on('unhandledRejection', (reason) => {
  console.error('Unhandled promise rejection:', reason);
});

app.use(cors());
app.use(express.json({ limit: '2mb' }));
installAsyncRouteWrapper(app);

// Convert DB snake_case rows to Flutter camelCase keys.
function toCamel(row) {
  if (!row) return row;
  const out = {};
  for (const [key, value] of Object.entries(row)) {
    const camel = key.replace(/_([a-z])/g, (_, c) => c.toUpperCase());
    out[camel] = value;
  }
  return out;
}

function toCamelList(rows) {
  return rows.map(toCamel);
}

// ---------- Health ----------
app.get('/api/health', async (_req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ ok: true, db: 'connected' });
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

// ---------- Auth ----------
app.post('/api/auth/login', async (req, res) => {
  const { username, password } = req.body;
  const result = await pool.query(
    'SELECT id FROM users WHERE username = $1 AND password = $2',
    [username, password],
  );
  res.json({ success: result.rows.length > 0 });
});

// ---------- Rates ----------
app.get('/api/rates', async (_req, res) => {
  await seedDefaultRates();
  const result = await pool.query('SELECT * FROM rates ORDER BY id');
  res.json(toCamelList(result.rows));
});

app.post('/api/rates/ensure-defaults', async (_req, res) => {
  await seedDefaultRates();
  res.json({ ok: true });
});

app.post('/api/admin/seed-rates', async (_req, res) => {
  await seedDefaultRates();
  res.json({ ok: true });
});

async function seedDefaultRates() {
  const count = await pool.query('SELECT COUNT(*)::int AS count FROM rates');
  if (count.rows[0].count > 0) return;
  await pool.query(
    `INSERT INTO rates (rate_name, rate_value) VALUES
      ('G.P RATE', ''),
      ('F.T RATE', ''),
      ('KACHA RATE', ''),
      ('S RATE', '')`,
  );
}

app.put('/api/rates/:id', async (req, res) => {
  const id = parsePositiveInt(req.params.id, 'rate id');
  const { rateName, rateValue, date, time } = req.body;
  const updated = await pool.query(
    'UPDATE rates SET rate_value = $1 WHERE id = $2 RETURNING *',
    [rateValue, id],
  );
  if (updated.rows.length > 0) {
    await pool.query(
      'INSERT INTO rate_history (rate_name, rate_value, date, time) VALUES ($1, $2, $3, $4)',
      [rateName, rateValue, date, time],
    );
  }
  res.json({ rowsAffected: updated.rowCount });
});

app.get('/api/rates/history', async (_req, res) => {
  const result = await pool.query('SELECT * FROM rate_history ORDER BY id DESC');
  res.json(toCamelList(result.rows));
});

app.get('/api/rates/stats', async (_req, res) => {
  const countResult = await pool.query('SELECT COUNT(*)::int AS count FROM rate_history');
  const latest = await pool.query('SELECT date, time FROM rate_history ORDER BY id DESC LIMIT 1');
  res.json({
    count: countResult.rows[0].count,
    lastDate: latest.rows[0]?.date ?? '',
    lastTime: latest.rows[0]?.time ?? '',
  });
});

// ---------- Customers ----------
app.get('/api/customers', async (_req, res) => {
  const result = await pool.query('SELECT * FROM customers ORDER BY id DESC');
  res.json(toCamelList(result.rows));
});

app.post('/api/customers', async (req, res) => {
  const c = req.body;
  const result = await pool.query(
    `INSERT INTO customers
      (name, mobile, city, cr, dr, dr_gross, dr_net, narration, balance_unit, bill_ref, date, time)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
     RETURNING id`,
    [c.name, c.mobile, c.city, c.cr, c.dr, c.drGross, c.drNet, c.narration,
     c.balanceUnit, c.billRef, c.date, c.time],
  );
  res.json({ id: result.rows[0].id });
});

app.delete('/api/customers/by-name/:name', async (req, res) => {
  const name = decodeNameParam(req.params.name);
  const result = await pool.query(
    'DELETE FROM customers WHERE LOWER(name) = LOWER($1)',
    [name],
  );
  res.json({ rowsAffected: result.rowCount });
});

app.delete('/api/customers/:id', async (req, res) => {
  const id = parsePositiveInt(req.params.id, 'customer id');
  const result = await pool.query('DELETE FROM customers WHERE id = $1', [id]);
  res.json({ rowsAffected: result.rowCount });
});

app.get('/api/customers/names', async (_req, res) => {
  const result = await pool.query('SELECT DISTINCT name FROM customers ORDER BY name');
  res.json(result.rows.map((r) => r.name));
});

app.get('/api/customers/:name/outstanding', async (req, res) => {
  const name = decodeURIComponent(req.params.name);
  const result = await pool.query(
    'SELECT * FROM customers WHERE LOWER(name) = LOWER($1)',
    [name],
  );
  let rupees = 0, grams = 0, crRupees = 0, drRupees = 0, crGrams = 0, drGrams = 0;
  for (const row of result.rows) {
    const cr = parseFloat(row.cr) || 0;
    const dr = parseFloat(row.dr) || 0;
    const unit = row.balance_unit || 'RUPEES';
    const billRef = (row.bill_ref || '').toString().trim();
    let net = dr - cr;
    if (unit === 'GRAMS' && !billRef) {
      const gold = parseFloat(row.dr_gross) || 0;
      if (Math.abs(gold) > 0.0005) net = gold;
    }
    if (unit === 'GRAMS') {
      grams += net; crGrams += cr; drGrams += dr;
    } else {
      rupees += net; crRupees += cr; drRupees += dr;
    }
  }
  res.json({ rupees, grams, crRupees, drRupees, crGrams, drGrams });
});

app.get('/api/party/phone', async (req, res) => {
  const { name, isCustomer } = req.query;
  const table = isCustomer === 'true' ? 'customers' : 'suppliers';
  const result = await pool.query(
    `SELECT mobile FROM ${table} WHERE name = $1 ORDER BY id DESC`,
    [name],
  );
  for (const row of result.rows) {
    const mobile = (row.mobile || '').trim();
    if (mobile) return res.json({ phone: mobile });
  }
  res.json({ phone: '' });
});

// ---------- Suppliers ----------
app.get('/api/suppliers', async (_req, res) => {
  const result = await pool.query('SELECT * FROM suppliers ORDER BY id DESC');
  res.json(toCamelList(result.rows));
});

app.post('/api/suppliers', async (req, res) => {
  const s = req.body;
  const result = await pool.query(
    `INSERT INTO suppliers
      (name, mobile, city, cr, dr, gross, net, narration, balance_unit, bill_ref, date, time)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
     RETURNING id`,
    [s.name, s.mobile, s.city, s.cr, s.dr, s.gross, s.net, s.narration,
     s.balanceUnit, s.billRef, s.date, s.time],
  );
  res.json({ id: result.rows[0].id });
});

app.delete('/api/suppliers/by-name/:name', async (req, res) => {
  const name = decodeNameParam(req.params.name);
  const result = await pool.query(
    'DELETE FROM suppliers WHERE LOWER(name) = LOWER($1)',
    [name],
  );
  res.json({ rowsAffected: result.rowCount });
});

app.delete('/api/suppliers/:id', async (req, res) => {
  const id = parsePositiveInt(req.params.id, 'supplier id');
  const result = await pool.query('DELETE FROM suppliers WHERE id = $1', [id]);
  res.json({ rowsAffected: result.rowCount });
});

app.get('/api/suppliers/names', async (_req, res) => {
  const result = await pool.query('SELECT DISTINCT name FROM suppliers ORDER BY name');
  res.json(result.rows.map((r) => r.name));
});

app.get('/api/suppliers/:name/outstanding', async (req, res) => {
  const name = decodeURIComponent(req.params.name);
  const result = await pool.query(
    'SELECT * FROM suppliers WHERE LOWER(name) = LOWER($1)',
    [name],
  );
  let rupees = 0, grams = 0, crRupees = 0, drRupees = 0, crGrams = 0, drGrams = 0;
  for (const row of result.rows) {
    const cr = parseFloat(row.cr) || 0;
    const dr = parseFloat(row.dr) || 0;
    const unit = row.balance_unit || 'RUPEES';
    const billRef = (row.bill_ref || '').toString().trim();
    let net = dr - cr;
    if (unit === 'GRAMS' && !billRef) {
      const gold = parseFloat(row.gross) || 0;
      if (Math.abs(gold) > 0.0005) net = gold;
    }
    if (unit === 'GRAMS') {
      grams += net; crGrams += cr; drGrams += dr;
    } else {
      rupees += net; crRupees += cr; drRupees += dr;
    }
  }
  res.json({ rupees, grams, crRupees, drRupees, crGrams, drGrams });
});

// ---------- Opening weight ----------
app.get('/api/opening-weight', async (_req, res) => {
  const result = await pool.query('SELECT * FROM opening_weight LIMIT 1');
  res.json(result.rows[0] ? toCamel(result.rows[0]) : null);
});

app.post('/api/opening-weight', async (req, res) => {
  const existing = await pool.query('SELECT id FROM opening_weight LIMIT 1');
  if (existing.rows.length > 0) {
    return res.status(409).json({ error: 'Opening weight already saved and locked.' });
  }
  const w = req.body;
  const result = await pool.query(
    `INSERT INTO opening_weight (g_pure_wt, fine_wt, kacha_wt, silver_wt, cash, date, time)
     VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING id`,
    [w.gPureWt, w.fineWt, w.kachaWt, w.silverWt, w.cash, w.date, w.time],
  );
  res.json({ id: result.rows[0].id });
});

// ---------- Transactions ----------
app.get('/api/transactions/next-bill-no', async (req, res) => {
  const type = req.query.type;
  const result = await pool.query(
    'SELECT COALESCE(MAX(bill_no), 0)::int AS max_bill FROM transactions WHERE transaction_type = $1',
    [type],
  );
  res.json({ billNo: result.rows[0].max_bill + 1 });
});

app.get('/api/transactions', async (req, res) => {
  const { type, date } = req.query;
  let result;
  if (type) {
    result = await pool.query(
      'SELECT * FROM transactions WHERE transaction_type = $1 ORDER BY id DESC',
      [type],
    );
  } else if (date) {
    result = await pool.query(
      'SELECT * FROM transactions WHERE date = $1 ORDER BY id DESC',
      [date],
    );
  } else {
    result = await pool.query('SELECT * FROM transactions ORDER BY id DESC');
  }
  res.json(toCamelList(result.rows));
});

app.post('/api/transactions', async (req, res) => {
  const t = req.body;
  const result = await pool.query(
    `INSERT INTO transactions
      (transaction_type, bill_no, party_name, items, total_wt, total_pure_wt, total_value,
       payment_mode, payment_amount, balance, balance_unit, staff_name, date, time,
       old_grams, old_rupees, new_grams, new_rupees, cash_to_gold, gold_rate_used,
       payment_items, receipt_purpose)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22)
     RETURNING id`,
    [t.transactionType, t.billNo, t.partyName, t.items, t.totalWt, t.totalPureWt,
     t.totalValue, t.paymentMode, t.paymentAmount, t.balance, t.balanceUnit,
     t.staffName, t.date, t.time, t.oldGrams, t.oldRupees, t.newGrams, t.newRupees,
     t.cashToGold, t.goldRateUsed, t.paymentItems, t.receiptPurpose],
  );
  res.json({ id: result.rows[0].id });
});

app.delete('/api/transactions/:id', async (req, res) => {
  const id = parsePositiveInt(req.params.id, 'transaction id');
  const result = await pool.query('DELETE FROM transactions WHERE id = $1', [id]);
  res.json({ rowsAffected: result.rowCount });
});

// ---------- Vouchers ----------
app.get('/api/vouchers/next-no', async (req, res) => {
  const type = req.query.type;
  const result = await pool.query(
    'SELECT COALESCE(MAX(voucher_no), 0)::int AS max_no FROM vouchers WHERE voucher_type = $1',
    [type],
  );
  res.json({ voucherNo: result.rows[0].max_no + 1 });
});

app.get('/api/vouchers', async (req, res) => {
  const { type } = req.query;
  const result = type
    ? await pool.query('SELECT * FROM vouchers WHERE voucher_type = $1 ORDER BY id DESC', [type])
    : await pool.query('SELECT * FROM vouchers ORDER BY id DESC');
  res.json(toCamelList(result.rows));
});

app.post('/api/vouchers', async (req, res) => {
  const v = req.body;
  const result = await pool.query(
    `INSERT INTO vouchers
      (voucher_type, voucher_no, party_name, is_customer, payment_mode, amount, amount_unit,
       cash_to_gold, gold_rate_used, old_grams, old_rupees, new_grams, new_rupees, narration, date, time)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16)
     RETURNING id`,
    [v.voucherType, v.voucherNo, v.partyName, v.isCustomer ? 1 : 0, v.paymentMode,
     v.amount, v.amountUnit, v.cashToGold, v.goldRateUsed, v.oldGrams, v.oldRupees,
     v.newGrams, v.newRupees, v.narration, v.date, v.time],
  );
  res.json({ id: result.rows[0].id });
});

app.delete('/api/vouchers/:id', async (req, res) => {
  const id = parsePositiveInt(req.params.id, 'voucher id');
  const result = await pool.query('DELETE FROM vouchers WHERE id = $1', [id]);
  res.json({ rowsAffected: result.rowCount });
});

// ---------- Current stock (computed) ----------
app.get('/api/stock/current', async (_req, res) => {
  const openingResult = await pool.query('SELECT * FROM opening_weight LIMIT 1');
  const opening = openingResult.rows[0] || {};

  const stock = {
    GWT: parseFloat(opening.g_pure_wt) || 0,
    FWT: parseFloat(opening.fine_wt) || 0,
    KWT: parseFloat(opening.kacha_wt) || 0,
    SWT: parseFloat(opening.silver_wt) || 0,
  };

  const txns = await pool.query('SELECT transaction_type, items FROM transactions');
  for (const row of txns.rows) {
    const sign = row.transaction_type === 'PURCHASE' ? 1 : -1;
    let items;
    try {
      items = JSON.parse(row.items || '[]');
    } catch {
      continue;
    }
    for (const item of items) {
      const type = item.type || '';
      const weight = parseFloat(item.weight) || 0;
      if (Object.prototype.hasOwnProperty.call(stock, type)) {
        stock[type] += sign * weight;
      }
    }
  }

  res.json(stock);
});

app.post('/api/admin/clear-transactions', async (_req, res) => {
  try {
    await pool.query('DELETE FROM transactions');
    await pool.query('DELETE FROM vouchers');
    // Sales/receipt ledger rows live on customers; purchase/payment on suppliers.
    await pool.query(
      `DELETE FROM customers
       WHERE bill_ref LIKE 'SAL-%' OR bill_ref LIKE 'RECEIPT-%'`,
    );
    await pool.query(
      `DELETE FROM suppliers
       WHERE bill_ref LIKE 'PUR-%' OR bill_ref LIKE 'PAYMENT-%'`,
    );
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: String(e) });
  }
});

app.post('/api/admin/reset', async (_req, res) => {
  try {
    await pool.query('DELETE FROM transactions');
    await pool.query('DELETE FROM vouchers');
    await pool.query('DELETE FROM opening_weight');
    await pool.query('DELETE FROM rate_history');
    await pool.query('DELETE FROM rates');
    await pool.query('DELETE FROM suppliers');
    await pool.query('DELETE FROM customers');
    await pool.query(
      `INSERT INTO rates (rate_name, rate_value) VALUES
        ('G.P RATE', ''),
        ('F.T RATE', ''),
        ('KACHA RATE', ''),
        ('S RATE', '')`,
    );
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: String(e) });
  }
});

// JSON error responses for failed API handlers (prevents process crashes).
app.use('/api', (err, _req, res, next) => {
  if (!err) return next();
  console.error('API error:', err);
  const status = err.status && err.status >= 400 && err.status < 600 ? err.status : 500;
  res.status(status).json({ error: err.message || 'Internal server error' });
});

// JSON 404 for unknown API routes (avoids HTML error pages in the Flutter client).
app.use('/api', (_req, res) => {
  res.status(404).json({ error: 'API route not found' });
});

const port = process.env.PORT || 3000;
app.listen(port, '0.0.0.0', () => {
  console.log(`Jewellery API listening on port ${port}`);
});
