# Data mobilization as the critical bottleneck for bias-aware biodiversity inference

Supporting analysis and figures for a BioScience Forum article arguing that
the main bottleneck in large-scale biodiversity inference is not modelling
capacity but the scarcity of "fit-for-inference" data: occurrence records
that carry interpretable metadata on sampling effort, protocol, and
non-detections (via Darwin Core terms like `eventID` and
`samplingProtocol`).

## Research question

For GBIF occurrence records, by year (~2015–2026):

1. What proportion have a non-empty `eventID`?
2. What proportion have a non-empty `samplingProtocol`?
3. (Secondary) What proportion of *datasets* are registered as type
   `SAMPLING_EVENT` vs `OCCURRENCE`/`CHECKLIST`, by registration year?

## Why not the live occurrence API

`occ_count(eventID = "*")` and `occ_search(facet = "eventID")` do **not**
filter or facet on field presence — they silently return the full,
unfiltered index count. This was confirmed empirically; see
`docs_briefing.md`. All record-level completeness metrics here are instead
computed from GBIF's public cloud snapshot (Parquet on S3), queried with
DuckDB.

## Scripts (`R/`), run in order

| Script | Purpose |
|---|---|
| `01_test_duckdb_httpfs.R` | Sanity check: DuckDB + httpfs can read a remote parquet file at all |
| `02_test_s3_gbif_access.R` | Sanity check: anonymous S3 access to the GBIF snapshot; confirms actual Parquet column names |
| `03_snapshot_query_single_year.R` | Small sample: one year only, scoped columns |
| `04_snapshot_query_all_years.R` | Full range 2015–2026, single grouped query |
| `05_registry_dataset_types.R` | Dataset-type breakdown by registration year, via the live registry API |
| `06_make_figure.R` | Produces the summary figures from the two result CSVs |

## Data source and caveats

GBIF's public S3 snapshot (documented at
https://github.com/gbif/occurrence/blob/master/aws-public-data.md) only
includes CC0/CC-BY records with coordinates that passed automated quality
checks. Percentages here describe that filtered subset, not the full GBIF
index. See `NOTE.md` for the exact snapshot date, confirmed field names,
and query runtime once the analysis has been run.

## Outputs

- `results/per_year_record_completeness.csv`
- `results/per_year_dataset_type.csv`
- `results/fig_record_completeness.png`
- `results/fig_dataset_type_share.png`
- `NOTE.md`
