-- 同じ複合インデックス (user_id, amount) でも、【先頭列】user_id を指定せず
-- 2列目の amount だけで絞ると、このインデックスは使えない（= 先頭列規則）。
-- amount は高選択性なのに Seq Scan に落ちる → 原因は選択性ではなく「列順」だと分かる。
-- 後段で amount 単独のインデックスを貼ると Index Scan に変わり、それを裏づけられる。
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM events WHERE amount = 500.00;
