# Phase 1b: sanity check anonymous access to the GBIF public occurrence
# snapshot on S3, and confirm the actual Parquet schema / column names
# (they may be lowercased relative to the Darwin Core term, e.g. `eventid`
# not `eventID`).
#
# Per briefing: five regional buckets exist. We try eu-central-1 first.
# If plain read_parquet() fails with a credentials error, DuckDB needs to
# be told to use unsigned/anonymous S3 access.

library(duckdb)

con <- dbConnect(duckdb())
dbExecute(con, "INSTALL httpfs;")
dbExecute(con, "LOAD httpfs;")

dbExecute(con, "SET s3_region='eu-central-1';")
dbExecute(con, "SET s3_url_style='path';")
# Anonymous/unsigned access to a public bucket (DuckDB >= 0.10 syntax)
try(dbExecute(con, "SET s3_use_ssl=true;"), silent = TRUE)
unsigned_ok <- tryCatch({
  dbExecute(con, "SET s3_access_key_id='';")
  dbExecute(con, "SET s3_secret_access_key='';")
  TRUE
}, error = function(e) FALSE)

# Try the CREATE SECRET style (current DuckDB way of doing anonymous S3)
try(dbExecute(con, "
  CREATE OR REPLACE SECRET gbif_s3 (
    TYPE S3,
    PROVIDER credential_chain,
    REGION 'eu-central-1'
  );
"), silent = TRUE)

# We don't know the exact current snapshot date yet, so first try to glob
# / list what's available. DuckDB can glob S3 paths.
bucket_glob <- "s3://gbif-open-data-eu-central-1/occurrence/*/occurrence.parquet/*.parquet"

cat("Attempting to list snapshot files via glob (may be slow / may fail)...\n")
listing <- tryCatch({
  dbGetQuery(con, sprintf(
    "SELECT file FROM glob('%s') LIMIT 20;", bucket_glob
  ))
}, error = function(e) {
  cat("Glob failed with error:\n", conditionMessage(e), "\n")
  NULL
})

print(listing)

if (is.null(listing) || nrow(listing) == 0) {
  stop("Could not list any files in the GBIF S3 bucket. STOPPING as instructed ",
       "rather than falling back to something else. Report this back before proceeding.")
}

# Pick one file to inspect schema
sample_file <- listing$file[1]
cat("Inspecting schema of:", sample_file, "\n")

schema <- dbGetQuery(con, sprintf("DESCRIBE SELECT * FROM read_parquet('%s') LIMIT 0;", sample_file))
print(schema)

# Confirm the specific columns we need exist under some casing
needed <- c("eventid", "samplingprotocol", "datasetkey", "year")
present <- tolower(schema$column_name)
for (n in needed) {
  cat(n, "present:", n %in% present, "\n")
}

dbDisconnect(con, shutdown = TRUE)
