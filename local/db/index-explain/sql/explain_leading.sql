-- 複合インデックス (user_id, amount) の【先頭列】user_id で絞る → インデックスが効く。
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM events WHERE user_id = 42;
