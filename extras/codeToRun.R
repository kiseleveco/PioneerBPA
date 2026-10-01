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
# PioneerBPA - study execution script
#
# This is the single file a site edits and runs to execute the study. Fill in
# the site-specific parameters below, then call PioneerBPA::execute().
# ==============================================================================

library(PioneerBPA)

# ------------------------------------------------------------------------------
# 1. Site-specific database connection  (edit these for every site)
# ------------------------------------------------------------------------------
source("../credentials.r")

JDBC <- "/home/a_kiselev/Jdbc"
connectionDetails <- DatabaseConnector::createConnectionDetails(
  dbms        = DBMS,
  user        = USER,
  password    = PASSWORD,
  server      = SERVER,
  port        = DB_PORT,
  pathToDriver = JDBC
)

# ------------------------------------------------------------------------------
# 2. Schema and table names
# ------------------------------------------------------------------------------
cdmDatabaseSchema        <- "marketscan_ccaemdcr_prod_merged"         # read-only CDM
vocabularyDatabaseSchema <- cdmDatabaseSchema                     # usually same as CDM
cohortDatabaseSchema     <- "marketscan_ccaemdcr_aug2025_results" # write-enabled; needs read/write/delete
cohortTable              <- "cohortBPA"
cohortTableNew           <- "cohortTableNew"
targetTable              <- "targetTable"

databaseId          <- "MarketScan_combined_2026"           # short identifier, no spaces
databaseName        <- "MarketScan combined 2026"
databaseDescription <- "MarketScan combined 2026"

outputFolder <- file.path("/home/a_kiselev/output", paste0(databaseId, "_BPA_v0.1"))

# Temp table emulation (Oracle / some Spark configs)
options(sqlRenderTempEmulationSchema = NULL)

# ------------------------------------------------------------------------------
# 3. Cohort definition ids  (from inst/settings/CohortsToCreate.csv)
# ------------------------------------------------------------------------------
target_metastasis <- 1768
target_bones      <- 1769
bpa_za            <- 1770
bpa_denosumab     <- 1771
adt               <- 1772
arpi              <- 1773
chemo             <- 1774

#Sensitivity arguments
bpaAa <- 1823
bpaAll  <- 1822
sensitivity <- FALSE

# ------------------------------------------------------------------------------
# 4. Run options
# ------------------------------------------------------------------------------
includeCohortStats <- TRUE
incrementalCohorts <- TRUE
generateCohorts <- FALSE
createTargetTable <- TRUE
createDerivedCohorts <- TRUE
runDiagnostics <- FALSE
runDrugExposureDiagnostics <- FALSE
runIRandTTEAnalysis <- FALSE
runComparativeEffectiveness <- FALSE
runTreatmentPatterns <- FALSE

## Comparative effectiveness (denosumab vs ZA) options
## RxNorm INGREDIENT concept ids for denosumab and zoledronic acid (and their
## descendants are excluded automatically). These MUST be filled in, otherwise
## the exposure leaks into the propensity model and invalidates it.
##   denosumab ingredient concept id  = <fill in>
##   zoledronic acid ingredient concept id = <fill in>

excludedCovariateConceptIds <- read.csv(
  system.file("settings", "conceptsToExclude.csv", package = "PioneerBPA"),
  header = FALSE
  )$V1

psMethod             <- "matching"   # or "weighting" (stabilized IPTW)

# ------------------------------------------------------------------------------
# 5. Execute the study
# ------------------------------------------------------------------------------
PioneerBPA::execute(
  connectionDetails        = connectionDetails,
  cdmDatabaseSchema        = cdmDatabaseSchema,
  vocabularyDatabaseSchema = vocabularyDatabaseSchema,
  cohortDatabaseSchema     = cohortDatabaseSchema,
  cohortTable              = cohortTable,
  cohortTableNew           = cohortTableNew,
  targetTable              = targetTable,
  outputFolder             = outputFolder,
  databaseId               = databaseId,
  databaseName             = databaseName,
  databaseDescription      = databaseDescription,
  targetMetastasis         = target_metastasis,
  targetBones              = target_bones,
  bpaZa                    = bpa_za,
  bpaDenosumab             = bpa_denosumab,
  bpaAa                    = bpaAa,
  bpaAll                   = bpaAll,
  sensitivity              = sensitivity,
  adt                      = adt,
  arpi                     = arpi,
  chemo                    = chemo,
  incrementalCohorts       = incrementalCohorts,
  includeCohortStats       = includeCohortStats,
  generateCohorts          = generateCohorts,
  createTargetTable        = createTargetTable,
  createDerivedCohorts     = createDerivedCohorts,
  runDiagnostics           = runDiagnostics,
  runDrugExposureDiagnostics = runDrugExposureDiagnostics,
  runIRandTTEAnalysis      = runIRandTTEAnalysis,
  runComparativeEffectiveness = runComparativeEffectiveness,
  runTreatmentPatterns        = runTreatmentPatterns,
  psMethod                    = psMethod,
  excludedCovariateConceptIds = excludedCovariateConceptIds
)
