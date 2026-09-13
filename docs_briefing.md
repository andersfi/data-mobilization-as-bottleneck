# Briefing: GBIF sampling-metadata completeness analysis

Paste the section below to Claude Code to start the session.

---

## Background

I am writing a BioScience Forum article arguing that the main bottleneck in
large-scale biodiversity inference is not modelling capacity but the
scarcity of "fit-for-inference" data — occurrence records that carry
interpretable metadata on sampling effort, protocol, and non-detections
(via Darwin Core terms like `eventID` and `samplingProtocol`).

I want an empirical figure showing how much of GBIF-mediated data actually
carries this information, and how that has changed over time. This would
be a real, reproducible, population-level statistic to support the
argument, rather than an assertion.

## The research question

For GBIF occurrence records, by year (roughly 2015–2026):
1. What proportion have a non-empty `eventID`?
2. What proportion have a non-empty `samplingProtocol`?
3. (Secondary) What proportion of *datasets* (not records) are registered
   as type `SAMPLING_EVENT` vs `OCCURRENCE`/`CHECKLIST`, by registration
   year?

Metric 1 and 2 are the priority — they measure whether individual records
can actually be linked to a sampling event, which is closer to the paper's
claim than dataset-level type alone (a dataset can be registered as
OCCURRENCE type and still carry eventID/samplingProtocol on every record).

## What I already tried, and what did not work

- `occ_count(eventID = "*")` in rgbif does **not** filter on presence of
  the field. It silently returns the same number as `occ_count()` with no
  filter at all (~3.8 billion — GBIF's whole index). No error is thrown,
  it just ignores the parameter.
- `occ_search(facet = "eventID", limit = 0)` behaves the same way —
  returns the full unfiltered count, and the facet itself comes back
  empty. So `eventID` is not a supported/indexed search or facet field in
  the occurrence API.
- Conclusion: **do not rely on the live occurrence search/count API for
  this.** It cannot answer the question we need.

## The approach that should work: GBIF's public cloud snapshot

GBIF publishes a full monthly snapshot of the occurrence corpus as public,
anonymously-readable Parquet files on AWS S3 (documented at
https://github.com/gbif/occurrence/blob/master/aws-public-data.md). It
only includes CC0/CC BY records with coordinates that passed automated
quality checks — note this filtering in any caveats.

Example bucket path pattern:
`s3://gbif-open-data-eu-central-1/occurrence/YYYY-MM-DD/occurrence.parquet/`
(check the bucket listing for the actual available snapshot dates/regions
— there are five regional buckets).

Recommended tool: **DuckDB**, run locally in R (or Python), no AWS account
needed, no cost. It can query remote Parquet over S3 directly via its
`httpfs` extension, reading only the columns needed (this is the point of
Parquet — column pruning avoids scanning the whole 180GB/month snapshot).

Known gotcha: anonymous S3 access sometimes requires telling DuckDB not to
attempt credential signing. If a plain `read_parquet('s3://...')` call
fails with a credentials error, these settings are the likely fix (exact
syntax may vary by DuckDB version — check current docs if this errors):

```sql
SET s3_region='eu-central-1';
SET s3_url_style='path';
-- and/or an explicit "unsigned" / anonymous access setting
```

Test the DuckDB + httpfs setup against a small public Parquet file over
plain HTTPS first, to separate "is DuckDB working" from "is S3 access
working," before pointing at the full GBIF snapshot.

## Deliverable

1. A working, documented R (or Python) script that:
   - Connects to the GBIF public snapshot via DuckDB (or falls back to
     Athena/Spark if DuckDB genuinely cannot handle it — but try DuckDB
     first, it's the simplest path)
   - Computes, per year from ~2015 to the most recent available snapshot:
     total occurrence count, count with non-empty `eventID`, count with
     non-empty `samplingProtocol`, and the two percentages
   - Also computes the dataset-type breakdown (SAMPLING_EVENT vs other)
     by registration year, using the GBIF registry API (`rgbif::datasets()`
     or `dataset_search()`/`dataset_export()` with `facet="type"` — this
     part *does* work via the live API, no need for the snapshot)
   - Saves the results as a clean CSV/tibble, one row per year, ready to
     plot
2. A simple line or bar chart (ggplot2 is fine) showing the two record-level
   percentages over time, and ideally a second panel for the dataset-type
   share over time
3. A short written note (a paragraph, not a report) stating: which
   snapshot date was used, exact field names as they appear in the
   Parquet schema (confirm — Parquet columns may be lowercased, e.g.
   `eventid` not `eventID`), any caveats about the CC0/CC BY/coordinate
   filtering built into the snapshot, and the actual query cost/runtime

## Constraints and preferences

- I want this to be fully reproducible — save the exact script and query,
  not just results, since this will go into a methods note or supplement.
- Keep the query scoped to only the columns needed (`eventID`,
  `samplingProtocol`, `datasetKey`, `year`) — do not pull full records.
- Test on a single year first before running the full 2015–2026 range, to
  catch schema or access problems cheaply.
- If DuckDB truly cannot reach the snapshot (network/firewall issues),
  tell me clearly rather than silently falling back to something that
  answers a different question — this happened already once this session
  with the occ_count() wildcard silently returning the wrong number, and
  I'd rather catch that kind of failure explicitly next time.
