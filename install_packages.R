# One-off: install every package SnapCart Lite needs.
pkgs <- c("shiny", "shinydashboard", "httr", "jsonlite", "ellmer", "tidyverse",
          "ranger", "caret", "forecast", "DT", "ggplot2", "lubridate", "readr",
          "here", "usethis", "base64enc", "rsconnect", "corrplot", "tidyr")
missing <- setdiff(pkgs, rownames(installed.packages()))
if (length(missing)) install.packages(missing)
cat("All packages installed.\n")
