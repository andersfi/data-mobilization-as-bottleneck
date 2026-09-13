# Phase 4: dataset-type breakdown (SAMPLING_EVENT vs OCCURRENCE/CHECKLIST)
# by dataset registration year, via the live GBIF registry API. This part
# works fine via rgbif -- unlike occurrence-level eventID/samplingProtocol
# presence, dataset type IS a proper indexed/faceted field.

library(rgbif)
library(dplyr)
library(purrr)

types <- c("OCCURRENCE", "SAMPLING_EVENT", "CHECKLIST", "METADATA")

# Registration year is not directly facetable via dataset_search's `facet`
# param in rgbif, so we page through dataset_search(type = <type>) and
# extract the `created` field's year client-side.
#
# Practical approach: page through dataset_search(type = <type>) in
# batches, pulling `created` (registration timestamp) for each dataset,
# and bucket by year. GBIF registry has on the order of tens of thousands
# of datasets total, so full pagination is feasible.

fetch_all_datasets_for_type <- function(type, page_limit = 1000) {
  all_records <- list()
  start <- 0
  repeat {
    page <- dataset_search(type = type, limit = page_limit, start = start)
    n <- length(page$data)
    if (is.null(page$data) || nrow(page$data) == 0) break
    all_records[[length(all_records) + 1]] <- page$data
    start <- start + page_limit
    if (start >= page$meta$count) break
  }
  bind_rows(all_records)
}

cat("Fetching dataset registry records by type (this pages through the full registry)...\n")

all_types <- map_dfr(types, function(t) {
  cat(" -", t, "\n")
  df <- fetch_all_datasets_for_type(t)
  if (nrow(df) == 0) return(tibble())
  df %>% mutate(type = t)
})

stopifnot(nrow(all_types) > 0)

# `created` is an ISO timestamp string; extract registration year
all_types <- all_types %>%
  mutate(registration_year = as.integer(substr(created, 1, 4)))

summary_by_year <- all_types %>%
  filter(!is.na(registration_year)) %>%
  count(registration_year, type) %>%
  tidyr::pivot_wider(names_from = type, values_from = n, values_fill = 0) %>%
  arrange(registration_year)

write.csv(summary_by_year, "results/per_year_dataset_type.csv", row.names = FALSE)
cat("Saved results/per_year_dataset_type.csv\n")
print(summary_by_year)
