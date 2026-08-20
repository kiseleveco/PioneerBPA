# Copyright 2026 Observational Health Data Sciences and Informatics
#
# This file is part of PioneerBPA
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# ==============================================================================
# Standalone post-processing: Wilson score confidence intervals for every
# cohort expressed as a proportion of the bone-metastasis index cohort (90100).
#
# It reads the CohortDiagnostics `cohort_count.csv` (columns: cohort_id,
# cohort_entries, cohort_subjects, database_id) found under the output
# directory, computes the proportion cohort_subjects / (90100 subjects) per
# database, and adds a Wilson 95% score interval. Results are written to
# `wilsonProportions.csv` in the output directory and printed to the console.
#
# Uses base R only - no package dependencies.
#
# Usage
# -----
#   Open this file in RStudio, set `outputDir` below to your study output
#   folder, then run the whole script (Ctrl/Cmd + Shift + Enter or Source).
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Input: output directory  (edit this to point at your study output folder)
# ------------------------------------------------------------------------------
outputDir <- "/Users/andreikiselev/Documents/Research_Questions/RQ2_BPA/output/MarketScan_BPA"

# Parameters
denominatorCohortId <- 90100    # bone-metastasis index cohort (the denominator)
confidenceLevel     <- 0.95

# ------------------------------------------------------------------------------
# 2. Locate the cohort count file
# ------------------------------------------------------------------------------
if (!dir.exists(outputDir) && !file.exists(outputDir)) {
  stop("Output directory not found: ", outputDir)
}

if (file.exists(outputDir) && !dir.exists(outputDir)) {
  # outputDir points directly at a CSV file
  countFile <- outputDir
} else {
  countFile <- list.files(outputDir,
                          pattern    = "^cohort_count\\.csv$",
                          recursive  = TRUE,
                          full.names = TRUE)
  if (length(countFile) == 0) {
    stop("Could not find 'cohort_count.csv' under ", outputDir,
         ". Point this script at the folder holding the CohortDiagnostics ",
         "output, or directly at the count CSV.")
  }
  if (length(countFile) > 1) {
    message("Multiple cohort_count.csv files found; using the first:\n  ",
            countFile[1])
    countFile <- countFile[1]
  }
}

counts <- read.csv(countFile, stringsAsFactors = FALSE)

# Require the columns we rely on.
required <- c("cohort_id", "cohort_subjects")
missing  <- setdiff(required, names(counts))
if (length(missing) > 0) {
  stop("Count file is missing required column(s): ", paste(missing, collapse = ", "))
}
# If there is no database_id column, treat everything as one database.
if (!"database_id" %in% names(counts)) {
  counts$database_id <- "All"
}

# ------------------------------------------------------------------------------
# 3. Wilson score interval for x successes out of n
# ------------------------------------------------------------------------------
wilsonInterval <- function(x, n, confidenceLevel = 0.95) {
  z   <- stats::qnorm(1 - (1 - confidenceLevel) / 2)
  p   <- x / n
  den <- 1 + z^2 / n
  centre    <- (p + z^2 / (2 * n)) / den
  halfWidth <- (z / den) * sqrt(p * (1 - p) / n + z^2 / (4 * n^2))
  data.frame(lower = centre - halfWidth,
             upper = centre + halfWidth)
}

# ------------------------------------------------------------------------------
# 4. Compute proportions and intervals, per database
# ------------------------------------------------------------------------------
results <- do.call(rbind, lapply(split(counts, counts$database_id), function(db) {
  databaseId <- db$database_id[1]

  denomRow <- db[db$cohort_id == denominatorCohortId, , drop = FALSE]
  if (nrow(denomRow) == 0) {
    warning("Database '", databaseId, "': denominator cohort ",
            denominatorCohortId, " not found - skipping.")
    return(NULL)
  }
  n <- denomRow$cohort_subjects[1]
  if (is.na(n) || n <= 0) {
    warning("Database '", databaseId, "': denominator cohort ",
            denominatorCohortId, " has no subjects - skipping.")
    return(NULL)
  }

  ci <- wilsonInterval(db$cohort_subjects, n, confidenceLevel)
  data.frame(
    database_id  = databaseId,
    cohort_id    = db$cohort_id,
    subjects     = db$cohort_subjects,
    denominator  = n,
    proportion   = db$cohort_subjects / n,
    ci_lower     = ci$lower,
    ci_upper     = ci$upper,
    stringsAsFactors = FALSE
  )
}))
row.names(results) <- NULL

# Order by database then cohort id for a stable, readable output.
results <- results[order(results$database_id, results$cohort_id), ]

# ------------------------------------------------------------------------------
# 5. Write and print
# ------------------------------------------------------------------------------
outDirForResult <- if (dir.exists(outputDir)) outputDir else dirname(countFile)
outFile <- file.path(outDirForResult, "wilsonProportions.csv")
write.csv(results, outFile, row.names = FALSE)
message("Wilson proportions written to: ", outFile)

# Console-friendly view as percentages.
pretty <- results
pretty$proportion <- round(pretty$proportion * 100, 2)
pretty$ci_lower   <- round(pretty$ci_lower   * 100, 2)
pretty$ci_upper   <- round(pretty$ci_upper   * 100, 2)
names(pretty)[names(pretty) == "proportion"] <- "pct"
names(pretty)[names(pretty) == "ci_lower"]   <- "ci_lower_pct"
names(pretty)[names(pretty) == "ci_upper"]   <- "ci_upper_pct"
print(pretty, row.names = FALSE)
