-- 高選択性の絞り込み: user_id は約10万種類 → 1値あたり数十行しか返らない。
-- インデックスが無ければ Seq Scan（300万行を全走査）。
-- user_id にインデックスを貼ると Index Scan（または Bitmap Index Scan）に変わり、
-- 実行時間と読んだブロック数（BUFFERS）が桁で減る。
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM events WHERE user_id = 42;
