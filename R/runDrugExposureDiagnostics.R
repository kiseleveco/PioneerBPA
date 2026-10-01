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

#' Run focused drug-exposure diagnostics on the derived cohorts
#'
#' Runs a targeted \code{CohortDiagnostics::executeDiagnostics} that characterises
#' the pre-built derived cohorts (in \code{cohortTableNew}) on \strong{drug
#' exposure only}, restricted to a single drug concept (and optionally its
#' descendants) over a single time window relative to cohort start. Every other
#' diagnostic (inclusion statistics, orphan / source concepts, incidence rate,
#' visit context, cohort relationship, ...) is switched off, so the export is
#' small and targeted.
#'
#' The derived cohort set is read from \code{inst/settings/DerivedCohorts.csv};
#' because these cohorts are materialised directly in the database, the
#' \code{json} and \code{sql} columns are supplied as placeholders.
#'
#' @param connectionDetails        DatabaseConnector connection details object.
#' @param cdmDatabaseSchema        Schema containing the OMOP CDM tables.
#' @param vocabularyDatabaseSchema Schema containing the vocabulary tables
#'   (typically the same as \code{cdmDatabaseSchema}).
#' @param cohortDatabaseSchema     Schema holding the derived cohort table.
#' @param cohortTableNew           Name of the derived cohort table to
#'   characterise.
#' @param databaseId               Short database identifier (no spaces).
#' @param databaseName             Human-readable database name.
#' @param databaseDescription      Longer database description.
#' @param outputFolder             Path where result files will be written
#'   (results go to \code{outputFolder/drugExposureDiagnostics}).
#' @param drugConceptId            Concept id to restrict drug exposure to.
#'   Default \code{21604147}.
#' @param addDescendants           Logical. Include descendants of
#'   \code{drugConceptId} (needed for class / ATC concepts). Default \code{TRUE}.
#' @param temporalStartDay,temporalEndDay Single time window (days relative to
#'   cohort start) to characterise over. Defaults \code{-30} and \code{365}.
#' @param minCellCount             Minimum cell count for censoring small counts.
#' @param packageName              Name of the package holding the settings.
#'
#' @export
runDrugExposureDiagnostics <- function(connectionDetails,
                                       cdmDatabaseSchema,
                                       vocabularyDatabaseSchema = cdmDatabaseSchema,
                                       cohortDatabaseSchema,
                                       cohortTableNew,
                                       databaseId,
                                       databaseName        = databaseId,
                                       databaseDescription = databaseId,
                                       outputFolder,
                                       drugConceptId    = 21604147,
                                       addDescendants   = TRUE,
                                       temporalStartDay = -30,
                                       temporalEndDay   = 365,
                                       minCellCount     = 5,
                                       packageName      = "PioneerBPA") {

  exportFolder <- file.path(outputFolder, "drugExposureDiagnostics")

  # --------------------------------------------------------------------------
  # 1. Cohort set (from inst/settings/DerivedCohorts.csv)
  # --------------------------------------------------------------------------
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

  # --------------------------------------------------------------------------
  # 2. Temporal covariate settings: drug exposure only, one concept, one window
  # --------------------------------------------------------------------------
  temporalCovariateSettings <- FeatureExtraction::createTemporalCovariateSettings(
    useDrugExposure             = TRUE,             # the ONLY covariate family
    includedCovariateConceptIds = drugConceptId,    # restrict to this concept ...
    addDescendantsToInclude     = addDescendants,   # ... and its descendants
    temporalStartDays           = temporalStartDay, # single window: -30 ...
    temporalEndDays             = temporalEndDay    # ... to +365 days
  )

  # --------------------------------------------------------------------------
  # 3. Run CohortDiagnostics - temporal characterization only
  # --------------------------------------------------------------------------
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

  invisible(NULL)
}
