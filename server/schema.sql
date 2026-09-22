-- Run on your Hostinger VPS PostgreSQL:
--   sudo -u postgres psql -f schema.sql

CREATE DATABASE jewellery_db;

\c jewellery_db

CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
  password TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS rates (
  id SERIAL PRIMARY KEY,
  rate_name TEXT NOT NULL,
  rate_value TEXT
);

CREATE TABLE IF NOT EXISTS rate_history (
  id SERIAL PRIMARY KEY,
  rate_name TEXT NOT NULL,
  rate_value TEXT NOT NULL,
  date TEXT NOT NULL,
  time TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS customers (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  mobile TEXT,
  city TEXT,
  cr TEXT,
  dr TEXT,
  dr_gross TEXT,
  dr_net TEXT,
  narration TEXT,
  balance_unit TEXT,
  bill_ref TEXT,
  date TEXT,
  time TEXT
);

CREATE TABLE IF NOT EXISTS suppliers (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  mobile TEXT,
  city TEXT,
  cr TEXT,
  dr TEXT,
  gross TEXT,
  net TEXT,
  narration TEXT,
  balance_unit TEXT,
  bill_ref TEXT,
  date TEXT,
  time TEXT
);

CREATE TABLE IF NOT EXISTS opening_weight (
  id SERIAL PRIMARY KEY,
  g_pure_wt TEXT,
  fine_wt TEXT,
  kacha_wt TEXT,
  silver_wt TEXT,
  cash TEXT,
  date TEXT,
  time TEXT
);

CREATE TABLE IF NOT EXISTS transactions (
  id SERIAL PRIMARY KEY,
  transaction_type TEXT NOT NULL,
  bill_no INTEGER NOT NULL,
  party_name TEXT,
  items TEXT NOT NULL,
  total_wt TEXT,
  total_pure_wt TEXT,
  total_value TEXT,
  payment_mode TEXT,
  payment_amount TEXT,
  balance TEXT,
  balance_unit TEXT,
  staff_name TEXT,
  date TEXT,
  time TEXT,
  old_grams TEXT,
  old_rupees TEXT,
  new_grams TEXT,
  new_rupees TEXT,
  cash_to_gold TEXT,
  gold_rate_used TEXT,
  payment_items TEXT,
  receipt_purpose TEXT,
  party_address TEXT,
  party_city TEXT,
  party_pincode TEXT,
  party_gstin TEXT,
  party_state TEXT,
  eway_bill TEXT,
  tds_applicable INTEGER,
  tds_amount TEXT,
  tcs_applicable INTEGER,
  tcs_amount TEXT,
  total_taxable TEXT,
  total_inclusive TEXT,
  round_off TEXT,
  grand_total TEXT
);

CREATE TABLE IF NOT EXISTS party_profiles (
  name_key TEXT NOT NULL,
  is_customer INTEGER NOT NULL,
  display_name TEXT NOT NULL,
  mobile TEXT,
  address TEXT,
  city TEXT,
  pincode TEXT,
  gstin TEXT,
  state TEXT,
  PRIMARY KEY (name_key, is_customer)
);

CREATE TABLE IF NOT EXISTS shop_settings (
  id INTEGER PRIMARY KEY,
  shop_name TEXT,
  address TEXT,
  phone TEXT,
  gstin TEXT,
  state TEXT,
  state_code TEXT
);

INSERT INTO shop_settings (id, shop_name, address, phone, gstin, state, state_code)
VALUES (1, '', '', '', '', '', '')
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS item_type_hsn (
  item_type TEXT PRIMARY KEY,
  hsn_code TEXT NOT NULL
);

INSERT INTO item_type_hsn (item_type, hsn_code) VALUES
  ('GWT', '7113'),
  ('FWT', '7113'),
  ('KWT', '7113'),
  ('SWT', '7114')
ON CONFLICT (item_type) DO NOTHING;

CREATE TABLE IF NOT EXISTS vouchers (
  id SERIAL PRIMARY KEY,
  voucher_type TEXT NOT NULL,
  voucher_no INTEGER NOT NULL,
  party_name TEXT,
  is_customer INTEGER NOT NULL,
  payment_mode TEXT,
  amount TEXT,
  amount_unit TEXT,
  cash_to_gold TEXT,
  gold_rate_used TEXT,
  old_grams TEXT,
  old_rupees TEXT,
  new_grams TEXT,
  new_rupees TEXT,
  narration TEXT,
  date TEXT,
  time TEXT
);

INSERT INTO users (username, password)
VALUES ('ADMIN', 'SVENSKA')
ON CONFLICT (username) DO NOTHING;

INSERT INTO rates (rate_name, rate_value) VALUES
  ('G.P RATE', ''),
  ('F.T RATE', ''),
  ('KACHA RATE', ''),
  ('S RATE', '')
ON CONFLICT DO NOTHING;
