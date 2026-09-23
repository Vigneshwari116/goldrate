-- Optional PO reference on purchase bills.

ALTER TABLE transactions ADD COLUMN IF NOT EXISTS po_no TEXT;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS po_date TEXT;
