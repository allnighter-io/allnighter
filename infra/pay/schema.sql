CREATE TABLE IF NOT EXISTS machines (
  machine_hash TEXT PRIMARY KEY,
  trial_started_at INTEGER NOT NULL,
  plan TEXT NOT NULL DEFAULT 'none',
  stripe_customer_id TEXT,
  stripe_subscription_id TEXT,
  paid_at INTEGER,
  email TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS founding_counter (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  sold INTEGER NOT NULL DEFAULT 0
);

INSERT OR IGNORE INTO founding_counter (id, sold) VALUES (1, 0);
