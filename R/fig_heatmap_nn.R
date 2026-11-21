# Varmekart + datasettvolum, nynorsk tekst og NaturAtlas/Gjærevoll-grønt.
# Les tabellen som gbif_metadata_datasets.R skriv (køyr han med COUNTRIES <- c("NO")).
# Bruk: Rscript R/fig_heatmap_nn.R [inndir] [utdir]   (standard: ".")

library(dplyr)
library(tidyr)
library(ggplot2)
library(patchwork)

args   <- commandArgs(trailingOnly = TRUE)
INDIR  <- if (length(args) >= 1) args[1] else "."
OUTDIR <- if (length(args) >= 2) args[2] else INDIR

## Fargar frå hotspot_website/src/config/project.yaml (primary, dark) ---------
GREEN      <- "#2a6e3f"
GREEN_DARK <- "#1d4d2a"
GREEN_PALE <- "#f3f7f4"

## Nynorske gruppenamn --------------------------------------------------------
NAMN_NN <- c(
  Aves = "Fuglar", Mammalia = "Pattedyr", Reptilia = "Krypdyr",
  Amphibia = "Amfibium", Actinopterygii = "Strålefinnefiskar",
  Chondrichthyes = "Bruskfiskar", Insecta = "Insekt", Arachnida = "Edderkoppdyr",
  Crustacea = "Krepsdyr", Gastropoda = "Sniglar", Bivalvia = "Muslingar",
  Annelida = "Leddormar", Tracheophyta = "Karplantar", Bryophyta = "Bladmosar",
  Marchantiophyta = "Levermosar", Agaricomycetes = "Hattsoppar",
  Lecanoromycetes = "Lav", Rhodophyta = "Raudalgar",
  Bacillariophyceae = "Kiselalgar", Foraminifera = "Foraminiferar"
)

## Kolonnar (same rekkjefølgje som METRIC_DEFS) -------------------------------
TERMAR <- c(
  with_eventid      = "eventID",
  with_parent_event = "parentEventID",
  with_protocol     = "samplingProtocol",
  with_sample_size  = "Innsatsinformasjon",
  with_quantity     = "organismQuantity",
  with_emof         = "eMoF-utviding",
  with_mof          = "MeasurementOrFact"
)

pct <- readr::read_csv(file.path(INDIR, "gbif_metadata_by_group_datasets.csv"),
                       show_col_types = FALSE) |>
  mutate(label = NAMN_NN[group])
stopifnot(!anyNA(pct$label))

ord  <- pct |> arrange(datasets_total) |> pull(label)
base <- pct |> mutate(label = factor(label, levels = ord))

komma <- function(x) sub(".", ",", x, fixed = TRUE)

hm <- base |>
  select(label, all_of(paste0("pct_", names(TERMAR)))) |>
  pivot_longer(-label, names_to = "metric", values_to = "p") |>
  mutate(metric = factor(sub("^pct_", "", metric),
                         levels = names(TERMAR), labels = TERMAR))

p_hm <- ggplot(hm, aes(metric, label, fill = p)) +
  geom_tile(colour = "white", linewidth = 0.6) +
  geom_text(aes(label = ifelse(p < 0.05, "<0,1", sprintf("%.0f", p)),
                colour = p > 50), size = 3, show.legend = FALSE) +
  scale_colour_manual(values = c(`TRUE` = "white", `FALSE` = "grey15")) +
  scale_fill_gradientn(colours = c(GREEN_PALE, "#b9d3c0", GREEN, GREEN_DARK),
                       values = c(0, 0.3, 0.7, 1), limits = c(0, 100)) +
  labs(x = NULL, y = NULL, fill = "%") +
  theme_minimal(base_size = 11) +
  theme(panel.grid = element_blank(),
        axis.text.x = element_text(angle = 30, hjust = 1))

p_vol <- ggplot(base, aes(datasets_total, label)) +
  geom_segment(aes(x = min(datasets_total) * 0.6, xend = datasets_total,
                   y = label, yend = label), colour = "#c9dbce", linewidth = 0.5) +
  geom_point(size = 2.2, colour = GREEN_DARK) +
  scale_x_log10(labels = scales::label_number(big.mark = " "),
                expand = expansion(mult = c(0.05, 0.15))) +
  labs(x = "Datasett (log)", y = NULL) +
  theme_minimal(base_size = 11) +
  theme(axis.text.y = element_blank(), panel.grid.major.y = element_blank())

fig <- p_hm + p_vol +
  plot_layout(widths = c(3, 1), guides = "collect") +
  plot_annotation(
    title = "Metadata om prøvetaking etter artsgruppe og Darwin Core-term – datasett",
    subtitle = "Del av datasetta i kvar gruppe som inneheld termen (%), Noreg") &
  theme(plot.title = element_text(colour = GREEN_DARK, face = "bold"))

ggsave(file.path(OUTDIR, "figD_ladder_heatmap_nn.pdf"), fig,
       width = 11, height = 6.5, device = cairo_pdf)
ggsave(file.path(OUTDIR, "figD_ladder_heatmap_nn.png"), fig,
       width = 11, height = 6.5, dpi = 300, bg = "white")
