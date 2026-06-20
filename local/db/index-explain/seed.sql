-- ============================================================
-- 初期データ投入: events テーブルに 300 万行を作る。
-- 数十行では Seq Scan も一瞬で終わり「桁違いの差」が体感できないので、
-- 本番想定のサイズを generate_series で生成する。
-- ============================================================

\timing on

DROP TABLE IF EXISTS events;

-- 主キー id には PostgreSQL が自動でインデックスを作る点に注意。
-- 実験で出し入れするのは「自分で貼る」インデックス（user_id / status / amount / email）。
CREATE TABLE events (
    id          bigserial PRIMARY KEY,
    user_id     bigint        NOT NULL,  -- 約10万種類 → 1値あたり数十行（高選択性）
    status      text          NOT NULL,  -- 4種類だけ（低選択性）
    amount      numeric(10,2) NOT NULL,
    email       text          NOT NULL,
    created_at  timestamptz   NOT NULL
);

INSERT INTO events (user_id, status, amount, email, created_at)
SELECT
    (random() * 100000)::bigint,                                   -- user_id
    (ARRAY['pending','paid','shipped','cancelled'])[1 + floor(random() * 4)::int],
    (random() * 1000)::numeric(10,2),                              -- amount
    'user' || (random() * 100000)::int || '@example.com',          -- email
    now() - (random() * 365 * 24 * 3600)::int * interval '1 second'-- 直近1年に散らす
FROM generate_series(1, 3000000);

-- VACUUM はテーブルの可視性マップを更新する → Index Only Scan（カバリング）が
-- 本来の「テーブル本体を読まない」挙動になるために必要。
-- ANALYZE はプランナの統計を最新化する → 推定行数が正しくなり、プラン選択が安定する。
VACUUM ANALYZE events;

SELECT count(*) AS rows, pg_size_pretty(pg_relation_size('events')) AS table_size
FROM events;
