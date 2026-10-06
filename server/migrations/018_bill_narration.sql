-- Optional bill-level narration on sales/purchase transactions (Flutter billNarration).

ALTER TABLE transactions ADD COLUMN IF NOT EXISTS bill_narration TEXT;
