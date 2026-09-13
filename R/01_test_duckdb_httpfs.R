# Phase 1a: sanity check that DuckDB + httpfs can read a remote parquet
# file at all, independent of GBIF/S3. This isolates "is DuckDB working"
# from "is S3 access working" (per briefing instructions).

library(duckdb)

con <- dbConnect(duckdb())

dbExecute(con, "INSTALL httpfs;")
dbExecute(con, "LOAD httpfs;")

# Small, well-known public parquet file served over plain HTTPS (NYC taxi
# sample hosted by DuckDB's own test-data bucket).
test_url <- "https://blobs.duckdb.org/data/taxi_2019_04.parquet"

res <- dbGetQuery(con, sprintf(
  "SELECT count(*) AS n FROM read_parquet('%s') LIMIT 1;", test_url
))

cat("Rows in test parquet file:", res$n, "\n")
stopifnot(res$n > 0)
cat("DuckDB + httpfs basic remote read: OK\n")

dbDisconnect(con, shutdown = TRUE)
