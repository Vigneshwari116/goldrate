-- GST billing (party profiles, shop header, HSN, transaction tax columns).
-- Safe to run multiple times on an existing jewellery_db / svenska DB.

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

ALTER TABLE transactions ADD COLUMN IF NOT EXISTS party_address TEXT;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS party_city TEXT;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS party_pincode TEXT;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS party_gstin TEXT;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS party_state TEXT;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS eway_bill TEXT;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS tds_applicable INTEGER;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS tds_amount TEXT;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS tcs_applicable INTEGER;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS tcs_amount TEXT;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS total_taxable TEXT;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS total_inclusive TEXT;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS round_off TEXT;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS grand_total TEXT;
