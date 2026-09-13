# Phase 2: SMALL SAMPLE. Query a single year only, scoped to the columns
# we need, against the GBIF public occurrence snapshot. Prints results and
# timing so they can be reviewed before scaling up to the full year range.
#
# Do not proceed to 04_snapshot_query_all_years.R until this has been run
# and the numbers look sane.

library(duckdb)

# Snapshot path is parameterised because the exact available date must be
# confirmed by 02_test_s3_gbif_access.R first.
snapshot_glob <- Sys.getenv(
  "GBIF_SNAPSHOT_GLOB",
  unset = "s3://gbif-open-data-eu-central-1/occurrence/2026-08-01/occurrence.parquet/*.parquet"
)

target_year <- as.integer(Sys.getenv("GBIF_TEST_YEAR", unset = "2023"))

con <- dbConnect(duckdb())
dbExecute(con, "INSTALL httpfs;")
dbExecute(con, "LOAD httpfs;")
dbExecute(con, "SET s3_region='eu-central-1';")
dbExecute(con, "SET s3_url_style='path';")
try(dbExecute(con, "
  CREATE OR REPLACE SECRET gbif_s3 (
    TYPE S3,
    PROVIDER credential_chain,
    REGION 'eu-central-1'
  );
"), silent = TRUE)

query <- sprintf("
  SELECT
    %d AS year,
    count(*) AS total,
    count(*) FILTER (WHERE eventid IS NOT NULL AND eventid != '') AS n_eventid,
    count(*) FILTER (WHERE samplingprotocol IS NOT NULL AND samplingprotocol != '') AS n_samplingprotocol
  FROM read_parquet('%s', hive_partitioning = false)
  WHERE year = %d;
", target_year, snapshot_glob, target_year)

cat("Running query for year", target_year, "...\n")
t0 <- Sys.time()
result <- dbGetQuery(con, query)
t1 <- Sys.time()

result$pct_eventid <- with(result, n_eventid / total * 100)
result$pct_samplingprotocol <- with(result, n_samplingprotocol / total * 100)

print(result)
cat("Query runtime:", round(as.numeric(t1 - t0, units = "secs"), 1), "seconds\n")

dbDisconnect(con, shutdown = TRUE)
