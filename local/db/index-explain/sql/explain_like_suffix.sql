-- 後方一致 '%xxx' は「先頭が決まらない」ので B-tree では範囲化できない。
-- text_pattern_ops のインデックスがあっても使えず、必ず Seq Scan に落ちる。
-- （部分一致を速くしたいなら trigram(pg_trgm) など別の仕組みが要る、という伏線。）
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM events WHERE email LIKE '%23@example.com';
