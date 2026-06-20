-- 取得する列が (user_id, amount) だけのクエリ。
--   ・(user_id) だけのインデックス → Index Scan でインデックスを辿った後、
--     amount を取りにテーブル本体へアクセスする（Heap Fetches が発生）。
--   ・(user_id) INCLUDE (amount) のカバリングインデックス → 必要な列が
--     インデックス内に揃うので、テーブル本体を読まない Index Only Scan になる。
-- 出力の "Heap Fetches:" の値が激減することで「本体を読まなくなった」と分かる
-- （seed.sql で VACUUM 済み = 可視性マップが立っていることが前提）。
EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id, amount FROM events WHERE user_id = 42;
