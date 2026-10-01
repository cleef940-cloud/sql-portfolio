-- News Articles Database Schema (PostgreSQL)
-- Stores ingested news articles with deduplication and audit metadata.
-- Requires the pg_trgm and pgvector extensions.

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE articles (
    id                  BIGSERIAL           PRIMARY KEY,

    -- Core identity (immutable)
    canonical_id        CHAR(64)            NOT NULL,                 -- sha256(canonical_url)
    canonical_url       TEXT                NOT NULL,
    content_hash        CHAR(64)            NOT NULL,                 -- sha256(normalised cleaned text) for dedup

    -- Ingest state
    status              TEXT                NOT NULL DEFAULT 'ingested'
                        CHECK (status IN ('ingested', 'duplicate', 'failed')),

    -- Source & discovery metadata (auditability)
    source              TEXT                NOT NULL,
    first_discovered    TIMESTAMPTZ         NOT NULL DEFAULT NOW(),
    first_ingested      TIMESTAMPTZ         NOT NULL DEFAULT NOW(),
    ingest_worker       TEXT,                                         -- which worker did it
    ingest_attempt      SMALLINT            NOT NULL DEFAULT 1,

    -- Article content (immutable after insert)
    title               TEXT                NOT NULL,
    clean_text          TEXT                NOT NULL,                 -- main article body
    html                TEXT,                                         -- optional full html
    published_at        TIMESTAMPTZ,
    language            CHAR(2),                                      -- iso 639-1

    -- Future NLP / embeddings
    embedding           VECTOR(1536),                                 -- pgvector
    embedding_model     TEXT,                                         -- e.g. 'text-embedding-3-small'
    embedding_version   SMALLINT            DEFAULT 1,

    -- Audit / provenance
    created_at          TIMESTAMPTZ         NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ         NOT NULL DEFAULT NOW()    -- only for metadata changes
);

-- One ingested/duplicate record per (article, source).
-- Enforced by the database so concurrent workers cannot insert the same article twice.
CREATE UNIQUE INDEX uq_canonical_source
    ON articles (canonical_id, source)
    WHERE status IN ('ingested', 'duplicate');

-- Supporting indexes
CREATE INDEX idx_articles_canonical_url_trgm    ON articles USING GIN (canonical_url gin_trgm_ops);
CREATE INDEX idx_articles_content_hash          ON articles (content_hash);
CREATE INDEX idx_articles_source_first_ingested ON articles (source, first_ingested DESC);
CREATE INDEX idx_articles_first_discovered      ON articles (first_discovered DESC);
CREATE INDEX idx_articles_published_at          ON articles (published_at DESC) WHERE published_at IS NOT NULL;

-- Full-text search (ranked)
CREATE INDEX idx_articles_fts ON articles USING GIN (
    to_tsvector('english', title || ' ' || clean_text)
);

-- Analytics views (refresh nightly/weekly)
CREATE MATERIALIZED VIEW mv_source_stats AS
SELECT
    source,
    count(*)                      AS total_articles,
    count(DISTINCT canonical_url) AS unique_urls,
    min(first_ingested)           AS first_ingest,
    max(first_ingested)           AS last_ingest,
    count(*) FILTER (WHERE published_at >= NOW() - INTERVAL '30 days') AS last_30d
FROM articles
GROUP BY source;

CREATE MATERIALIZED VIEW mv_timeline_daily AS
SELECT
    date_trunc('day', first_ingested) AS day,
    source,
    count(*) AS articles_ingested
FROM articles
GROUP BY day, source
ORDER BY day DESC;
