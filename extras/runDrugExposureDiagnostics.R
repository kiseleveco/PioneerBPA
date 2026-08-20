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
# Focused CohortDiagnostics run: DRUG EXPOSURE only, restricted to a single
# drug concept (21604147) and a single time window of -30 to +365 days relative
# to cohort start.
#
# This characterises the derived cohorts (pre-built in `cohortTableNew`) on just
# that one drug concept and its descendants, so the resulting export is small
# and targeted. Every other diagnostic (inclusion stats, orphan/source
# concepts, incidence, visit context, cohort relationship, ...) is switched off.
#
# Open this file in RStudio, edit the variables in section 1, then run it.
# ==============================================================================

library(CohortDiagnostics)

# ------------------------------------------------------------------------------
# 1. Inputs  (edit these)
# ------------------------------------------------------------------------------
source("../credentials.r")

JDBC <- "/home/a_kiselev/Jdbc"
connectionDetails <- DatabaseConnector::createConnectionDetails(
  dbms         = DBMS,
  user         = USER,
  password     = PASSWORD,
  server       = SERVER,
  port         = DB_PORT,
  pathToDriver = JDBC
)

cdmDatabaseSchema        <- "marketscan_ccaemdcr_aug2025"
vocabularyDatabaseSchema <- cdmDatabaseSchema
cohortDatabaseSchema     <- "marketscan_ccaemdcr_aug2025_results"
cohortTableNew           <- "cohortTableNew"        # pre-built derived cohorts

databaseId          <- "MarketScan"
databaseName        <- "MarketScan aug2025"
databaseDescription <- "MarketScan aug2025"

outputFolder <- file.path("/home/a_kiselev/output", paste0(databaseId, "_BPA"))
exportFolder <- file.path(outputFolder, "drugExposureDiagnostics")

minCellCount <- 5
packageName  <- "PioneerBPA"

# -- The single drug concept and time window to characterise -------------------
drugConceptId    <- 21604147   # restrict drug exposure to this concept ...
addDescendants   <- TRUE       # ... and its descendants (needed for class/ATC concepts)
temporalStartDay <- -30        # window start, relative to cohort start
temporalEndDay   <- 365        # window end, relative to cohort start

# ------------------------------------------------------------------------------
# 2. Cohort set (from inst/settings/DerivedCohorts.csv)
# ------------------------------------------------------------------------------
csvPath <- system.file("settings", "DerivedCohorts.csv", package = packageName)
cohorts <- read.csv(csvPath, stringsAsFactors = FALSE)

# These cohorts are pre-built in cohortTableNew, so json/sql are placeholders.
cohortDefinitionSet <- data.frame(
  cohortId   = as.double(cohorts$cohortId),
  cohortName = cohorts$cohortName,
  json       = "{}",
  sql        = "SELECT 1;",
  stringsAsFactors = FALSE
)

# ------------------------------------------------------------------------------
# 3. Temporal covariate settings: drug exposure only, one concept, one window
# ------------------------------------------------------------------------------
temporalCovariateSettings <- FeatureExtraction::createTemporalCovariateSettings(
  useDrugExposure             = TRUE,             # the ONLY covariate family
  includedCovariateConceptIds = drugConceptId,    # restrict to this concept ...
  addDescendantsToInclude     = addDescendants,   # ... and its descendants
  temporalStartDays           = temporalStartDay, # single window: -30 ...
  temporalEndDays             = temporalEndDay    # ... to +365 days
)

# ------------------------------------------------------------------------------
# 4. Run CohortDiagnostics - temporal characterization only
# ------------------------------------------------------------------------------
cohortTableNames <- CohortGenerator::getCohortTableNames(cohortTable = cohortTableNew)

CohortDiagnostics::executeDiagnostics(
  cohortDefinitionSet       = cohortDefinitionSet,
  exportFolder              = exportFolder,
  databaseId                = databaseId,
  databaseName              = databaseName,
  databaseDescription       = databaseDescription,
  connectionDetails         = connectionDetails,
  cdmDatabaseSchema         = cdmDatabaseSchema,
  cohortDatabaseSchema      = cohortDatabaseSchema,
  cohortTable               = cohortTableNew,
  cohortTableNames          = cohortTableNames,
  vocabularyDatabaseSchema  = vocabularyDatabaseSchema,
  cdmVersion                = 5,
  minCellCount              = minCellCount,
  temporalCovariateSettings = temporalCovariateSettings,
  # everything except the temporal drug-exposure characterization is off
  runInclusionStatistics            = FALSE,
  runIncludedSourceConcepts         = FALSE,
  runOrphanConcepts                 = FALSE,
  runBreakdownIndexEvents           = FALSE,
  runVisitContext                   = FALSE,
  runIncidenceRate                  = FALSE,
  runTimeSeries                     = FALSE,
  runCohortRelationship             = FALSE,
  runTemporalCohortCharacterization = TRUE
)
