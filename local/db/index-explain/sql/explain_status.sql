-- 低選択性の絞り込み: status は4種類だけ → 'paid' で全体の約25%（数十万行）がヒット。
-- たとえ status にインデックスを貼っても、これだけ多くを返すなら
-- 「インデックスを辿ってから本体を読む」より「全部順に読む」方が速い。
-- → プランナはあえて Seq Scan を選ぶ。「インデックス＝常に速い」ではない代表例。
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM events WHERE status = 'paid';
