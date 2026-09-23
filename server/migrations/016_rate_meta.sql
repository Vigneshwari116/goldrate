-- Last daily-rate save timestamp (updates even when values unchanged).

CREATE TABLE IF NOT EXISTS rate_meta (
  id INTEGER PRIMARY KEY,
  last_date TEXT NOT NULL DEFAULT '',
  last_time TEXT NOT NULL DEFAULT ''
);

INSERT INTO rate_meta (id, last_date, last_time)
VALUES (1, '', '')
ON CONFLICT (id) DO NOTHING;
