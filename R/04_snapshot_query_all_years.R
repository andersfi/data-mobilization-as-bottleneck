# Phase 3: full year range (2015 to most recent available snapshot year),
# scoped to only the columns needed. Only run after 03_snapshot_query_single_year.R
# has been validated.

library(duckdb)
library(dplyr)

snapshot_glob <- Sys.getenv(
  "GBIF_SNAPSHOT_GLOB",
  unset = "s3://gbif-open-data-eu-central-1/occurrence/2026-08-01/occurrence.parquet/*.parquet"
)

years <- 2015:2026

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

# Single pass over the snapshot with GROUP BY year, rather than one query
# per year -- avoids rescanning the dataset N times.
query <- sprintf("
  SELECT
    year,
    count(*) AS total,
    count(*) FILTER (WHERE eventid IS NOT NULL AND eventid != '') AS n_eventid,
    count(*) FILTER (WHERE samplingprotocol IS NOT NULL AND samplingprotocol != '') AS n_samplingprotocol
  FROM read_parquet('%s', hive_partitioning = false)
  WHERE year BETWEEN %d AND %d
  GROUP BY year
  ORDER BY year;
", snapshot_glob, min(years), max(years))

cat("Running full-range query for", min(years), "-", max(years), "...\n")
t0 <- Sys.time()
results <- dbGetQuery(con, query)
t1 <- Sys.time()
cat("Query runtime:", round(as.numeric(t1 - t0, units = "mins"), 2), "minutes\n")

results <- results %>%
  mutate(
    pct_eventid = n_eventid / total * 100,
    pct_samplingprotocol = n_samplingprotocol / total * 100
  ) %>%
  arrange(year)

write.csv(results, "results/per_year_record_completeness.csv", row.names = FALSE)
cat("Saved results/per_year_record_completeness.csv\n")
print(results)

dbDisconnect(con, shutdown = TRUE)
