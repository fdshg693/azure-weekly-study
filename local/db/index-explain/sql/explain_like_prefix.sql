-- 前方一致 LIKE 'xxx%' は「先頭が決まっている」ので B-tree の範囲検索に変換できる。
-- ただし通常ロケールの DB では、それを使えるのは text_pattern_ops 演算子クラスで
-- 貼ったインデックスのとき（justfile の e5-index がそれを作る）。効けば Index Scan。
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM events WHERE email LIKE 'user123%';
