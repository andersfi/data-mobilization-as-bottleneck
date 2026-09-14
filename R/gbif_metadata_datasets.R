# ==============================================================================
#  SAMPLING METADATA IN GBIF -- DATASET-LEVEL VIEW
#
#  Companion to the record-level script. Same groups, same terms, same figures,
#  but the unit is the DATASET rather than the occurrence record.
#
#  The two answer different questions:
#    record-level   "most of the data you would download is unusable"
#    dataset-level  "most publishers do not do this"
#  A large gap between them means a few enormous opportunistic datasets are
#  driving the record-level picture -- which implies a different intervention
#  than a field-wide norm does.
#
#  >>> CAVEAT, state this in any caption <<<
#  A dataset counts as carrying a term if AT LEAST ONE of its records does.
#  That is a deliberately weak criterion: one structured record in a million
#  qualifies the whole dataset. It is the right criterion for a big-picture
#  overview and the wrong one for a claim about data practice. SECTION 9 also
#  writes per-dataset shares so a threshold version can be built later without
#  refetching.
#
#  ---------------------------------------------------------------------------
#  WHERE TO CHANGE WHAT
#  ---------------------------------------------------------------------------
#   SECTION 0   CONFIGURATION      scope, years, labels, facet limit, output.
#   SECTION 1   BACKGROUND         why COL XR and not the backbone. No code.
#   SECTION 2   GROUPS             taxon table and exemplar species.
#   SECTION 3   METRICS            the ladder of Darwin Core terms.
#   SECTION 4   HELPERS            transport, predicates, dataset faceting.
#   SECTION 5   RESOLUTION         group names -> COL taxon keys.
#   SECTION 6   EXTENSION CHECK    verifies the extension URIs.
#   SECTION 7   VALIDATION
#   SECTION 8   SWEEP              per-dataset counts per group per metric.
#   SECTION 9   TABLES             dataset counts, and per-dataset shares for
#                                  the later drill-down.
#   SECTION 10  FIGURES            per-metric panels, heatmap + volume.
#   SECTION 11  PROVENANCE
#
#  Requires: httr2, dplyr, tidyr, tibble, purrr, readr, ggplot2, patchwork, scales
# ==============================================================================

library(httr2)
library(dplyr)
library(tidyr)
library(purrr)
library(ggplot2)
library(patchwork)

`%||%` <- function(a, b) if (is.null(a)) b else a


# ==============================================================================
# SECTION 0 -- CONFIGURATION
# ==============================================================================

## Geographic scope ------------------------------------------------------------
## NULL | c("NO") | c("NO","SJ")
## COUNTRY is the interpreted country of the record, not PUBLISHING_COUNTRY.
COUNTRIES <- NULL

YEARS  <- 1950:2026
LABEL  <- "vernacular"     # "vernacular" | "vernacular_no" | "group"
OUTDIR <- "."

## Facet limit for DATASET_KEY --------------------------------------------------
## Globally there are tens of thousands of datasets. If a facet comes back with
## exactly this many buckets the result is truncated and SECTION 8 warns.
FACET_LIMIT <- 100000

## Validation: gbif.org Aves + 2025 + present + eventID, at the scope set above.
GROUND_TRUTH <- if (is.null(COUNTRIES)) 8358962 else NA_real_

dir.create(OUTDIR, showWarnings = FALSE, recursive = TRUE)
op <- function(f) file.path(OUTDIR, f)

SEARCH_URL <- "https://api.gbif.org/v1/occurrence/search/predicate"
OCC_URL    <- "https://api.gbif.org/v1/occurrence/search"
COL        <- "7ddf754f-d193-4cc9-b351-99906754a03b"   # Catalogue of Life XR
UA         <- "NTNU Gjaerevoll Centre - dataset metadata audit"


# ==============================================================================
# SECTION 1 -- BACKGROUND (no code)
# ==============================================================================
#
# GBIF runs two taxonomies with different key spaces:
#   GBIF Backbone (frozen)  integer keys. Stripped -- Gadus morhua's lineage is
#                           Chordata > Gadiformes, no class rank at all.
#   Catalogue of Life XR    alphanumeric keys (Teleostei = 8V4VD). What
#                           gbif.org shows and what the occurrence index uses
#                           when checklistKey is pinned.
#
# No v1 endpoint bridges them. Confirmed dead ends, do not retry:
#   /species/match [+checklistKey]  -> matchType NONE for higher taxa
#   /species?datasetKey=COL&name=   -> ChecklistBank keys the index rejects;
#                                      the count returns 0, not an error
#   /species/8V4VD                  -> HTTP 400, backbone integers only
#
# Keys are read from an occurrence record's COL classification instead.
# Counting uses POST /occurrence/search/predicate, because isNotNull exists only
# in the predicate language and not as a GET parameter.


# ==============================================================================
# SECTION 2 -- GROUPS
# ==============================================================================
# Each slot is c(exemplar species, taxon name expected in its lineage).
# Multiple slots are UNIONED. Reptilia is the only composed group. Plants are
# cut coarse -- do NOT add Liliopsida etc. alongside Tracheophyta, they sit
# inside it and TAXON_KEY matching is transitive.

GROUPS <- tibble::tribble(
  ~group,            ~vernacular,                  ~vernacular_no,  ~slots,
  "Aves",            "Birds",                      "Fugler",        list(c("Passer domesticus",     "Aves")),
  "Mammalia",        "Mammals",                    "Pattedyr",      list(c("Vulpes vulpes",         "Mammalia")),
  "Reptilia",        "Reptiles",                   "Krypdyr",       list(c("Lacerta agilis",        "Squamata"),
                                                                         c("Chelonia mydas",        "Testudines"),
                                                                         c("Crocodylus niloticus",  "Crocodylia")),
  "Amphibia",        "Amphibians",                 "Amfibier",      list(c("Rana temporaria",       "Amphibia")),
  "Actinopterygii",  "Ray-finned fishes",          "Beinfisker",    list(c("Gadus morhua",          "Actinopterygii")),
  "Chondrichthyes",  "Sharks, rays and chimaeras", "Bruskfisker",   list(c("Squalus acanthias",     "Chondrichthyes")),
  "Insecta",         "Insects",                    "Insekter",      list(c("Apis mellifera",        "Insecta")),
  "Arachnida",       "Arachnids",                  "Edderkoppdyr",  list(c("Araneus diadematus",    "Arachnida")),
  "Crustacea",       "Crustaceans",                "Krepsdyr",      list(c("Cancer pagurus",        "Crustacea")),
  "Gastropoda",      "Snails and slugs",           "Snegler",       list(c("Helix pomatia",         "Gastropoda")),
  "Bivalvia",        "Bivalves",                   "Muslinger",     list(c("Mytilus edulis",        "Bivalvia")),
  "Annelida",        "Segmented worms",            "Leddormer",     list(c("Lumbricus terrestris",  "Annelida")),
  "Tracheophyta",    "Vascular plants",            "Karplanter",    list(c("Bellis perennis",       "Tracheophyta")),
  "Bryophyta",       "Mosses",                     "Bladmoser",     list(c("Polytrichum commune",   "Bryophyta")),
  "Marchantiophyta", "Liverworts",                 "Levermoser",    list(c("Marchantia polymorpha", "Marchantiophyta")),
  "Agaricomycetes",  "Mushroom-forming fungi",     "Hattsopper",    list(c("Amanita muscaria",      "Agaricomycetes")),
  "Lecanoromycetes", "Lichens",                    "Lav",           list(c("Cladonia rangiferina",  "Lecanoromycetes")),
  "Rhodophyta",      "Red algae",                  "Rodalger",      list(c("Palmaria palmata",      "Rhodophyta")),
  "Bacillariophyceae","Diatoms",                   "Kiselalger",    list(c("Asterionella formosa",  "Bacillariophyceae")),
  "Foraminifera",    "Foraminifera",               "Foraminiferer", list(c("Ammonia beccarii",      "Foraminifera"))
)


# ==============================================================================
# SECTION 3 -- METRICS
# ==============================================================================
# Terms NOT available in the occurrence index: taxonomicScope, samplingEffort,
# eventType -- Humboldt terms, not indexed.
#
# NOTE ON HUMBOLDT: the Humboldt Extension for Ecological Inventories does not
# appear among GBIF's indexed extensions at all -- a global DWCA_EXTENSION facet
# returns 21 values and none is under rs.tdwg.org/eco/. GBIF only surfaces
# extensions it has interpretation support for, so say "not represented in
# GBIF's indexed extensions", not "nobody uses it".
#
# CAVEAT for the caption: a record in either measurement extension says
# measurements exist, not that they describe sampling effort. eMoF carries water
# temperature as readily as trawl duration -- a ceiling on structured
# measurement, not a count of effort data.

METRIC_DEFS <- tibble::tribble(
  ~metric,             ~label,               ~kind,       ~arg,
  "with_eventid",      "eventID",            "notnull",   "EVENT_ID",
  "with_parent_event", "parentEventID",      "notnull",   "PARENT_EVENT_ID",
  "with_protocol",     "samplingProtocol",   "notnull",   "SAMPLING_PROTOCOL",
  "with_sample_size",  "sampleSizeValue",    "notnull",   "SAMPLE_SIZE_VALUE",
  "with_quantity",     "organismQuantity",   "notnull",   "ORGANISM_QUANTITY",
  "with_emof",         "eMoF extension",     "extension", "http://rs.iobis.org/obis/terms/ExtendedMeasurementOrFact",
  "with_mof",          "MeasurementOrFact",  "extension", "http://rs.tdwg.org/dwc/terms/MeasurementOrFact"
)


# ==============================================================================
# SECTION 4 -- HELPERS
# ==============================================================================

gbif_post <- function(body) {
  request(SEARCH_URL) |>
    req_body_json(body, auto_unbox = TRUE) |>
    req_user_agent(UA) |>
    req_throttle(capacity = 10, fill_time_s = 1) |>
    req_retry(max_tries = 4) |>
    req_perform() |>
    resp_body_json(simplifyVector = FALSE)
}

p_and     <- function(...) list(type = "and", predicates = compact(list(...)))
p_or      <- function(preds) list(type = "or", predicates = preds)
p_equals  <- function(key, value) list(type = "equals", key = key, value = as.character(value))
p_notnull <- function(parameter) list(type = "isNotNull", parameter = parameter)
p_range   <- function(key, from, to) {
  list(type = "range", key = key,
       value = list(gte = as.character(from), lte = as.character(to)))
}
p_taxon   <- function(key) list(type = "equals", key = "TAXON_KEY",
                                value = as.character(key), checklistKey = COL)
p_any     <- function(preds) if (length(preds) == 1) preds[[1]] else p_or(preds)
p_taxa    <- function(keys) p_any(map(keys, p_taxon))

p_scope <- if (is.null(COUNTRIES)) NULL else
  p_any(map(COUNTRIES, \(cc) p_equals("COUNTRY", cc)))
p_years <- p_range("YEAR", min(YEARS), max(YEARS))

gbif_count <- function(predicate) gbif_post(list(predicate = predicate, limit = 0))$count

#' Facet a predicate, returning one row per bucket.
gbif_facet <- function(predicate, field, n = 500) {
  res <- gbif_post(list(predicate = predicate, facets = list(field),
                        facetLimit = n, limit = 0))
  cts <- res$facets[[1]]$counts
  if (length(cts) == 0) return(tibble::tibble(value = character(), n = numeric()))
  tibble::tibble(value = map_chr(cts, "name"), n = as.numeric(map_dbl(cts, "count")))
}

#' Datasets matching a predicate, with per-dataset record counts.
#' Warns if the facet looks truncated -- a silent cap would understate every
#' number downstream.
gbif_datasets <- function(predicate, what = "") {
  d <- gbif_facet(predicate, "DATASET_KEY", n = FACET_LIMIT)
  if (nrow(d) >= FACET_LIMIT) {
    warning("DATASET_KEY facet hit FACET_LIMIT (", FACET_LIMIT, ") for ", what,
            " -- result is truncated. Narrow the scope or paginate.")
  }
  d
}


# ==============================================================================
# SECTION 5 -- RESOLUTION
# ==============================================================================

col_key <- function(species, want_name) {
  occ <- request(OCC_URL) |>
    req_url_query(scientificName = species, limit = 1) |>
    req_user_agent(UA) |> req_retry(max_tries = 3) |>
    req_perform() |> resp_body_json(simplifyVector = FALSE) |> _$results

  fail <- function(note) tibble::tibble(name = want_name, key = NA_character_,
                                        rank = NA_character_, exemplar = species,
                                        note = note)
  if (length(occ) == 0) return(fail(sprintf("no occurrence for exemplar '%s'", species)))
  lin <- occ[[1]]$classifications[[COL]]$classification
  if (is.null(lin)) return(fail("no COL classification on record"))
  hit <- keep(lin, \(x) identical(x$name, want_name))
  if (length(hit) != 1) {
    return(fail(sprintf("'%s' not in lineage: %s", want_name,
                        paste(map_chr(lin, \(x) sprintf("%s [%s]", x$name, x$rank)),
                              collapse = " > "))))
  }
  tibble::tibble(name = want_name, key = hit[[1]]$key, rank = hit[[1]]$rank,
                 exemplar = species, note = NA_character_)
}

message("Resolving group keys via the occurrence index (COL XR)...")
resolution <- GROUPS |>
  select(group, slots) |>
  mutate(res = map(slots, \(sl) map_dfr(sl, \(s) col_key(s[[1]], s[[2]])))) |>
  select(group, res) |> unnest(res)

print(as.data.frame(resolution), row.names = FALSE)

failed <- filter(resolution, is.na(key))
if (nrow(failed) > 0) {
  message("\nDROPPED (unresolved):")
  walk2(failed$group, failed$note, \(g, n) message("  ", g, ": ", n))
}
bad        <- unique(failed$group)
dropped    <- filter(GROUPS, group %in% bad)
resolution <- filter(resolution, !group %in% bad)
GROUPS     <- filter(GROUPS,     !group %in% bad)
if (nrow(resolution) == 0) stop("Nothing resolved.", call. = FALSE)
message("\nProceeding with ", nrow(GROUPS), " of ",
        nrow(GROUPS) + nrow(dropped), " groups.")

keys_by_group <- split(resolution$key, resolution$group)
readr::write_csv(resolution, op("gbif_taxon_resolution.csv"))


# ==============================================================================
# SECTION 6 -- EXTENSION CHECK
# ==============================================================================

ext_seen <- gbif_facet(p_and(p_scope, p_years), "DWCA_EXTENSION", n = 200)
message("\nDWCA_EXTENSION values in use at this scope:")
print(as.data.frame(ext_seen), row.names = FALSE)

ext_wanted  <- filter(METRIC_DEFS, kind == "extension")$arg
missing_ext <- setdiff(ext_wanted, ext_seen$value)
if (length(missing_ext) > 0) {
  warning("Extension URI not present at this scope -- the metric will be 0:\n  ",
          paste(missing_ext, collapse = "\n  "),
          "\n  At a national scope this may be a real absence rather than a ",
          "wrong URI; confirm unscoped with ",
          "gbif_count(p_equals('DWCA_EXTENSION', <uri>)).")
}


metric_pred <- function(kind, arg) {
  switch(kind,
         notnull   = p_notnull(arg),
         extension = p_equals("DWCA_EXTENSION", arg),
         stop("unknown metric kind: ", kind))
}


# ==============================================================================
# SECTION 7 -- VALIDATION
# ==============================================================================
# A wrong key space returns 0, not an error.

aves_key <- resolution$key[resolution$group == "Aves"]
n_val <- gbif_count(p_and(p_taxon(aves_key), p_scope,
                          p_equals("YEAR", 2025),
                          p_equals("OCCURRENCE_STATUS", "PRESENT"),
                          p_notnull("EVENT_ID")))
if (n_val == 0) stop("Aves validation returned 0 -- key space, checklistKey or ",
                     "scope is wrong.", call. = FALSE)

if (is.na(GROUND_TRUTH)) {
  message(sprintf("\nValidation: Aves/2025/eventID = %s (non-zero).",
                  format(n_val, big.mark = " ")))
} else {
  rel <- abs(n_val - GROUND_TRUTH) / GROUND_TRUTH
  message(sprintf("\nValidation: API = %s | portal = %s | %.2f%% apart",
                  format(n_val, big.mark = " "),
                  format(GROUND_TRUTH, big.mark = " "), 100 * rel))
  if (rel > 0.02) stop("Validation failed. If you changed COUNTRIES, update ",
                       "GROUND_TRUTH.", call. = FALSE)
}


# ==============================================================================
# SECTION 8 -- SWEEP
# ==============================================================================
# Keeps the full dataset-key lists, not just counts. That costs nothing extra
# and is what makes the threshold version (SECTION 9) and the later drill-down
# possible without refetching.

message("\nFetching ", nrow(GROUPS), " groups x ", nrow(METRIC_DEFS) + 1,
        " metrics...")

ds_raw <- imap_dfr(keys_by_group, \(keys, grp) {
  message("  ", grp)
  base_pred <- function(extra = NULL) {
    p_and(p_taxa(keys), p_scope, p_equals("OCCURRENCE_STATUS", "PRESENT"),
          p_years, extra)
  }
  bind_rows(
    gbif_datasets(base_pred(), paste(grp, "baseline")) |> mutate(metric = "datasets"),
    pmap_dfr(METRIC_DEFS, \(metric, label, kind, arg) {
      gbif_datasets(base_pred(metric_pred(kind, arg)), paste(grp, label)) |>
        mutate(metric = metric)
    })
  ) |> rename(dataset_key = value, records = n) |> mutate(group = grp, .before = 1)
})


# ==============================================================================
# SECTION 9 -- TABLES
# ==============================================================================

metric_lv <- c("datasets", METRIC_DEFS$metric)

## Dataset counts per group per metric ------------------------------------------
counts <- ds_raw |>
  count(group, metric, name = "n_datasets") |>
  pivot_wider(names_from = metric, values_from = n_datasets, values_fill = 0)

absent <- setdiff(metric_lv, names(counts))
if (length(absent) > 0) {
  message("\nNo datasets found for: ", paste(absent, collapse = ", "))
  counts[absent] <- 0
}

totals <- counts |>
  left_join(select(GROUPS, group, vernacular, vernacular_no), by = "group") |>
  rename(datasets_total = datasets) |>
  arrange(desc(datasets_total))

pct <- totals |>
  mutate(across(all_of(METRIC_DEFS$metric), \(x) 100 * x / datasets_total,
                .names = "pct_{.col}"))

print(as.data.frame(pct |> select(group, datasets_total, starts_with("pct_"))),
      row.names = FALSE, digits = 3)

## Per-dataset shares, for the drill-down later ---------------------------------
## share = fraction of that dataset's records (for that group) carrying the term.
## A threshold version of the figure is then just a filter on share.
shares <- ds_raw |>
  filter(metric != "datasets") |>
  rename(records_with = records) |>
  left_join(ds_raw |> filter(metric == "datasets") |>
              select(group, dataset_key, records_total = records),
            by = c("group", "dataset_key")) |>
  mutate(share = records_with / records_total)

readr::write_csv(pct,    op("gbif_metadata_by_group_datasets.csv"))
readr::write_csv(shares, op("gbif_dataset_shares.csv"))


# ==============================================================================
# SECTION 10 -- FIGURES
# ==============================================================================

scope_txt <- if (is.null(COUNTRIES)) "global" else paste(COUNTRIES, collapse = "+")
ord  <- pct |> mutate(l = .data[[LABEL]]) |> arrange(datasets_total) |> pull(l)
base <- pct |> mutate(label = factor(.data[[LABEL]], levels = ord))

vol_panel <- function() {
  ggplot(base, aes(datasets_total, label)) +
    geom_segment(aes(x = min(datasets_total) * 0.6, xend = datasets_total,
                     y = label, yend = label), colour = "grey80", linewidth = 0.5) +
    geom_point(size = 2.2, colour = "grey25") +
    scale_x_log10(labels = scales::label_number(scale_cut = scales::cut_short_scale()),
                  expand = expansion(mult = c(0.05, 0.15))) +
    labs(x = "Datasets (log)", y = NULL) +
    theme_minimal(base_size = 11) +
    theme(axis.text.y = element_blank(), panel.grid.major.y = element_blank())
}

## ---- One panel per metric ----------------------------------------------------
fig1_for <- function(metric, label_txt) {
  d <- base |>
    mutate(has   =  100 * .data[[metric]] / datasets_total,
           lacks = -100 * (datasets_total - .data[[metric]]) / datasets_total) |>
    select(label, datasets_total, has, lacks)

  pa_dat <- d |>
    pivot_longer(c(lacks, has), names_to = "side", values_to = "p") |>
    mutate(side = factor(side, levels = c("lacks", "has"),
                         labels = c(paste("No", label_txt), label_txt)))

  pa <- ggplot(pa_dat, aes(p, label, fill = side)) +
    geom_col(width = 0.72) +
    geom_vline(xintercept = 0, linewidth = 0.4) +
    geom_text(data = d, aes(x = has, y = label, label = sprintf("%.1f%%", has)),
              inherit.aes = FALSE, hjust = -0.25, size = 3, colour = "grey25") +
    scale_x_continuous(limits = c(-100, 120), breaks = seq(-100, 100, 25),
                       labels = \(x) paste0(abs(x), "%")) +
    scale_fill_manual(values = setNames(c("#c0392b", "#2c6fbb"),
                                        c(paste("No", label_txt), label_txt))) +
    labs(x = "Share of the group's datasets", y = NULL, fill = NULL) +
    theme_minimal(base_size = 11) +
    theme(legend.position = "top", panel.grid.major.y = element_blank())

  pa + vol_panel() + plot_layout(widths = c(3, 1)) +
    plot_annotation(
      title = sprintf("Datasets containing %s", label_txt),
      subtitle = sprintf("%s, %d-%d; a dataset counts if any record carries the term",
                         scope_txt, min(YEARS), max(YEARS)))
}

pwalk(METRIC_DEFS, \(metric, label, kind, arg) {
  ggsave(op(sprintf("figD1_%s.pdf", metric)), fig1_for(metric, label),
         width = 10, height = 6)
})

## ---- Heatmap + volume --------------------------------------------------------
hm <- pct |>
  mutate(label = factor(.data[[LABEL]], levels = ord)) |>
  select(label, all_of(paste0("pct_", METRIC_DEFS$metric))) |>
  pivot_longer(-label, names_to = "metric", values_to = "p") |>
  mutate(metric = factor(sub("^pct_", "", metric),
                         levels = METRIC_DEFS$metric, labels = METRIC_DEFS$label))

p_hm <- ggplot(hm, aes(metric, label, fill = p)) +
  geom_tile(colour = "white", linewidth = 0.6) +
  geom_text(aes(label = ifelse(p < 0.05, "<0.1", sprintf("%.0f", p)),
                colour = p > 55), size = 3, show.legend = FALSE) +
  scale_colour_manual(values = c(`TRUE` = "white", `FALSE` = "grey15")) +
  scale_fill_gradient(low = "#f7f7f7", high = "#1b4f8a", limits = c(0, 100)) +
  labs(x = NULL, y = NULL, fill = "%") +
  theme_minimal(base_size = 11) +
  theme(panel.grid = element_blank(),
        axis.text.x = element_text(angle = 30, hjust = 1))

fig_ladder <- p_hm + vol_panel() +
  plot_layout(widths = c(3, 1), guides = "collect") +
  plot_annotation(
    title = "Sampling metadata by group and Darwin Core term -- datasets",
    subtitle = sprintf("%% of each group's datasets containing the term (%s)", scope_txt))

ggsave(op("figD_ladder_heatmap.pdf"), fig_ladder, width = 11, height = 6.5)
print(fig_ladder)


# ==============================================================================
# SECTION 11 -- PROVENANCE
# ==============================================================================

saveRDS(list(
  accessed    = format(Sys.time(), tz = "UTC", usetz = TRUE),
  unit        = "dataset",
  criterion   = "dataset carries term if >= 1 record does",
  endpoint    = SEARCH_URL,
  checklist   = c(name = "Catalogue of Life XR", key = COL),
  countries   = COUNTRIES %||% "global",
  years       = range(YEARS),
  facet_limit = FACET_LIMIT,
  metrics     = METRIC_DEFS,
  extensions  = ext_seen,
  groups      = GROUPS,
  dropped     = dropped,
  resolution  = resolution,
  validation  = list(aves_2025_eventid = n_val, portal = GROUND_TRUTH)
), op("gbif_dataset_provenance.rds"))

message("\nDone. Wrote tables and figures to ", normalizePath(OUTDIR))
