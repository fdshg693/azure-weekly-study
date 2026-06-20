-- 列に関数を噛ませた条件 lower(email) = ... 。
-- インデックスは「列 email そのもの」に貼られているので、lower(email) には使えず Seq Scan。
-- 対策は【式インデックス】 CREATE INDEX ... ON events (lower(email)) を貼ること
-- （justfile の e6-fix）。これで Index Scan に変わる = 関数結果に対して索引している。
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM events WHERE lower(email) = 'user42@example.com';
