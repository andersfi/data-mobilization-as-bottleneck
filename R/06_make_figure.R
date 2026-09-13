# Phase 5: figure. Reads the two summary CSVs and produces a two-panel
# chart: record-level completeness (%eventID, %samplingProtocol) over time,
# and dataset-type share over registration year.

library(dplyr)
library(tidyr)
library(ggplot2)

record_df <- read.csv("results/per_year_record_completeness.csv")
dataset_df <- read.csv("results/per_year_dataset_type.csv")

# Panel 1: record-level completeness
record_long <- record_df %>%
  select(year, pct_eventid, pct_samplingprotocol) %>%
  pivot_longer(-year, names_to = "metric", values_to = "pct") %>%
  mutate(metric = recode(metric,
    pct_eventid = "eventID present",
    pct_samplingprotocol = "samplingProtocol present"
  ))

p1 <- ggplot(record_long, aes(x = year, y = pct, color = metric)) +
  geom_line(linewidth = 1) +
  geom_point(size = 2) +
  scale_y_continuous(limits = c(0, 100)) +
  labs(
    title = "Share of GBIF occurrence records carrying sampling metadata",
    x = "Year", y = "% of records", color = NULL
  ) +
  theme_minimal(base_size = 13)

ggsave("results/fig_record_completeness.png", p1, width = 8, height = 5, dpi = 300)

# Panel 2: dataset type share over registration year
type_cols <- setdiff(names(dataset_df), "registration_year")
dataset_long <- dataset_df %>%
  pivot_longer(all_of(type_cols), names_to = "type", values_to = "n") %>%
  group_by(registration_year) %>%
  mutate(share = n / sum(n) * 100) %>%
  ungroup()

p2 <- ggplot(dataset_long, aes(x = registration_year, y = share, fill = type)) +
  geom_col() +
  labs(
    title = "Dataset type share by registration year",
    x = "Registration year", y = "% of datasets registered", fill = "Type"
  ) +
  theme_minimal(base_size = 13)

ggsave("results/fig_dataset_type_share.png", p2, width = 8, height = 5, dpi = 300)

cat("Saved results/fig_record_completeness.png and results/fig_dataset_type_share.png\n")
