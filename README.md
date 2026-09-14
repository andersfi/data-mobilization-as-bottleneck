# Data mobilization as the critical bottleneck for bias-aware biodiversity inference

Supporting analysis and figures for a BioScience Forum article arguing that
the main bottleneck in large-scale biodiversity inference is not modelling
capacity but the scarcity of "fit-for-inference" data: occurrence records
that carry interpretable metadata on sampling effort, protocol, and
non-detections (via Darwin Core terms like `eventID` and
`samplingProtocol`).

## What this measures

The proportion of GBIF-mediated occurrence records that carry interpretable
sampling metadata — the Darwin Core terms that determine whether a record
can be used for inference rather than just presence-mapping. Results are
broken down by taxonomic group.

Two scripts, two units of analysis:

| Script | Unit | Question it answers |
|---|---|---|
| `R/gbif_metadata_records.R` | occurrence record | how much of the data you would download is usable |
| `R/gbif_metadata_datasets.R` | dataset | how many publishers structure their data this way |

The gap between them is informative. If a group is low by record but high
by dataset, a few enormous opportunistic datasets dominate the
record-level picture — which implies a different intervention than a
field-wide norm does.

### Terms measured

`eventID`, `parentEventID`, `samplingProtocol`, `sampleSizeValue`,
`organismQuantity`, plus presence of the OBIS ExtendedMeasurementOrFact and
Darwin Core MeasurementOrFact extensions.

The terms are **not nested**. A record can carry `organismQuantity`
without `sampleSizeValue`. Read the figures as independent proportions,
not as a funnel.

## Method

Counting uses `POST /occurrence/search/predicate`. This matters: the
ordinary GET occurrence search has no "field is present" parameter, so the
question cannot be asked through it. `isNotNull` exists only in GBIF's
predicate language — the same language the download API uses — and the
predicate search endpoint accepts it while answering live and supporting
facets. One request returns counts per year for a predicate the GET API
cannot express.

rgbif wraps the GET endpoint only, so it cannot express these queries.
`occ_count(eventID = "*")` silently returns the unfiltered index count —
this was the first dead end and the reason the scripts talk to the
predicate API directly via `httr2` instead of going through rgbif.

## Taxonomy

GBIF runs two taxonomies in parallel with **different key spaces**:

- **GBIF Backbone** (frozen) — integer keys. Now stripped: *Gadus morhua*'s
  lineage is `Chordata > Gadiformes`, with no class rank at all. Ray-finned
  fishes cannot be selected by name.
- **Catalogue of Life XR** — alphanumeric keys (`Teleostei` = `8V4VD`).
  What gbif.org displays, and what the occurrence index matches when
  `checklistKey` is pinned on the predicate.

These scripts use COL XR throughout.

No v1 endpoint bridges the two key spaces. Confirmed dead ends — do not
retry:

| Attempt | Result |
|---|---|
| `/species/match?name=Amphibia` | `matchType: NONE` |
| `/species/match?...&checklistKey=COL` | also `NONE` |
| `/species?datasetKey=COL&name=Teleostei` | returns ChecklistBank internal key `299480021`; the occurrence index rejects it and the count comes back **0, not an error** |
| `/species/8V4VD` | HTTP 400 — backbone integers only |
| `/species/search?q=Amphibia` unscoped | searches all of ChecklistBank, returns five different "Amphibia" from five checklists |

Keys are therefore resolved **through the occurrence index**: fetch one
record for a known exemplar species and read the key out of its COL
classification. Each group in the script names an exemplar and the taxon
expected above it in that species' lineage. If the name is absent, the
error prints the full lineage so the correct name can be read off
directly.

Verified end to end: `TAXON_KEY = 8V4VD` with `checklistKey` pinned to COL
returns 114,951,837 records for Teleostei, matching gbif.org exactly.

### Taxonomic groups

Twenty groups, chosen to be recognisable to non-specialists and stable
across classification revisions rather than pinned to a single rank.
Loosely inspired by Troudet et al. (2017), *Sci Rep* 7:9132, but not a
direct comparison.

- Plants are cut coarse: Tracheophyta / Bryophyta / Marchantiophyta —
  three non-overlapping siblings. Do **not** add Liliopsida, Pinopsida,
  Polypodiopsida or Magnoliopsida alongside Tracheophyta; they sit inside
  it and `TAXON_KEY` matching is transitive.
- **Reptilia** is the only composed group, built from Squamata +
  Testudines + Crocodylia. It is genuinely paraphyletic (excludes birds),
  so composing it carries meaning rather than patching a classification
  gap. Rhynchocephalia is omitted — two extant species.
- Unions are built as OR-of-equals on `TAXON_KEY`. Because matching is
  transitive and OR matches each record once, overlapping keys cannot
  double-count. Summing separate per-taxon queries would.

## Validation

Both scripts refuse to proceed on a failed check. Two guards:

1. **Non-zero.** A wrong key space returns `0`, not an error. This is the
   failure mode that caused the most trouble during development.
2. **Against the portal.** Aves + 2025 + occurrence status present +
   eventID must reproduce the figure read off gbif.org (8,358,962
   globally). Changing `COUNTRIES` sets the expected value to `NA`, which
   keeps the non-zero check and skips the numeric one — read a new figure
   off the portal if you want it back.

Groups that fail resolution are dropped with a printed reason rather than
aborting the run, and the dropped set is recorded in the provenance file.

## Caveats to carry into any caption

- **Dataset-level criterion is deliberately weak.** A dataset counts as
  carrying a term if *at least one* of its records does — one structured
  record in a million qualifies the whole dataset. Right for a
  big-picture overview, wrong for a claim about data practice. The
  dataset script writes `gbif_dataset_shares.csv` (per-dataset fraction of
  records carrying each term) so a threshold version can be built later
  without refetching.
- **Measurement extensions are a ceiling, not a count of effort data.**
  eMoF carries water temperature as readily as trawl duration. Presence
  means measurements exist, not that they describe sampling effort.
- **The year axis is `eventDate`, not publication date.** A 1960 record
  with an `eventID` means a modern dataset, published with event
  structure, covering historical fieldwork. Any temporal reading conflates
  changing field practice with changing digitisation practice. Year is
  retained in the output but no temporal figure is drawn.
- **The Humboldt Extension for Ecological Inventories is not measurable
  here.** A global `DWCA_EXTENSION` facet returns 21 values and none is
  under `rs.tdwg.org/eco/`. GBIF only surfaces extensions it has
  interpretation support for, so the correct statement is "not
  represented in GBIF's indexed extensions" — not "nobody uses it".
  Related Humboldt terms (`taxonomicScope`, `samplingEffort`,
  `eventType`) are likewise not indexed in the occurrence search.
- **Scope.** `COUNTRY` is GBIF's interpreted country of the record, not
  `PUBLISHING_COUNTRY` (where the publishing institution sits). `NO`
  excludes Svalbard and Jan Mayen — use `c("NO", "SJ")` for both.

## Figures

Each script produces one panel per metric, plus a combined heatmap. Panels
pair a **linear** proportion axis with a **log** volume axis, side by
side.

Do not merge these onto one axis. An earlier version used an inverse
hyperbolic sine scale for a diverging with/without bar, and on a log-like
scale a 10:1 count ratio renders as near-equal bars — the picture
contradicted the printed percentages. asinh was appropriate in Troudet et
al. because their quantity was a signed *deviation* spanning ±500M; a
with/without split is a proportion and needs a linear axis.

## Configuration

Everything intended to be edited is in SECTION 0 of each script:
geographic scope, year range, display language (English or Norwegian
vernacular names), output directory, and thresholds. SECTION 2 holds the
taxon table. The section map at the top of each file says where
everything else lives.

Run global and national scopes into separate output directories — both
write identical filenames.

## Reproducibility

Each run writes a provenance `.rds` (`gbif_query_provenance.rds` for the
record-level script, `gbif_dataset_provenance.rds` for the dataset-level
one) containing the timestamp, endpoint, checklist key, scope, year range,
metric definitions, the extension list as indexed that day, the group
table, dropped groups, resolved keys with their exemplars, and the
validation result. Keep it with the figures.

## Running

```r
# from the project root
renv::restore()   # installs the pinned package versions from renv.lock
source("R/gbif_metadata_records.R")
source("R/gbif_metadata_datasets.R")
```

Both scripts write their outputs (CSVs, PDFs, the provenance `.rds`) to
`OUTDIR` as set in SECTION 0 (default: project root). These outputs are
not committed — see `.gitignore` — because they are cheaply regenerated
and scope-dependent (global vs. national runs overwrite each other's
default filenames).

Requires: `httr2`, `dplyr`, `tidyr`, `tibble`, `purrr`, `readr`,
`ggplot2`, `patchwork`, `scales`, pinned in `renv.lock`.
