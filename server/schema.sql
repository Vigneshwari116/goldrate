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
  receipt_purpose TEXT
);

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
