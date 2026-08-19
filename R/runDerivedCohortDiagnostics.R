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

#' Run CohortDiagnostics on the derived cohorts
#'
#' Runs \code{CohortDiagnostics::executeDiagnostics} against the pre-built
#' derived cohort table (\code{cohortTableNew}). The derived cohort set is read
#' from \code{inst/settings/DerivedCohorts.csv}; because these cohorts are
#' materialised directly in the database rather than generated from Circe
#' expressions, the \code{json} and \code{sql} columns are supplied as
#' placeholders and the concept-based diagnostics are disabled.
#'
#' A custom temporal covariate setting characterises the cohorts across a set of
#' time windows relative to cohort start (see the \code{temporalStartDays} /
#' \code{temporalEndDays} vectors below).
#'
#' @param connectionDetails        DatabaseConnector connection details object.
#' @param cdmDatabaseSchema        Schema containing the OMOP CDM tables.
#' @param cohortDatabaseSchema     Schema holding the derived cohort table.
#' @param cohortTableNew           Name of the derived cohort table to
#'   characterise.
#' @param exportFolder             Path where diagnostics results will be
#'   written.
#' @param databaseId               Short database identifier (no spaces).
#' @param databaseName             Human-readable database name.
#' @param databaseDescription      Longer database description.
#' @param vocabularyDatabaseSchema Schema containing the vocabulary tables
#'   (typically the same as \code{cdmDatabaseSchema}).
#' @param minCellCount             Minimum cell count for censoring small
#'   counts in the exported results.
#' @param packageName              Name of the package holding the settings
#'   resources.
#'
#' @export
runDerivedCohortDiagnostics <- function(connectionDetails,
                                        cdmDatabaseSchema,
                                        cohortDatabaseSchema,
                                        cohortTableNew,
                                        exportFolder,
                                        databaseId,
                                        databaseName        = databaseId,
                                        databaseDescription = databaseId,
                                        vocabularyDatabaseSchema = cdmDatabaseSchema,
                                        minCellCount        = 5,
                                        packageName         = "PioneerBPA") {

  # --- 1. cohort set from the CSV -------------------------------------------
  csvPath <- system.file("settings", "DerivedCohorts.csv", package = packageName)
  cohorts <- read.csv(csvPath, stringsAsFactors = FALSE)

  # CohortDiagnostics needs cohortId, cohortName, json, sql.
  # These cohorts are pre-built in cohortTableNew, so json/sql are placeholders.
  cohortDefinitionSet <- data.frame(
    cohortId   = as.double(cohorts$cohortId),
    cohortName = cohorts$cohortName,
    json       = "{}",
    sql        = "SELECT 1;",
    stringsAsFactors = FALSE
  )

  # --- 2. custom temporal covariate settings --------------------------------
  # Time windows (days, relative to cohort start) to characterise over.
  temporalCovariateSettings <- FeatureExtraction::createTemporalCovariateSettings(
    useDemographicsGender               = TRUE,
    useDemographicsAge                  = TRUE,
    useDemographicsAgeGroup             = TRUE,
    useDemographicsRace                 = TRUE,
    useDemographicsEthnicity            = TRUE,
    useDemographicsIndexYear            = TRUE,
    useDemographicsIndexMonth           = TRUE,
    useDemographicsIndexYearMonth       = TRUE,
    useDemographicsPriorObservationTime = TRUE,
    useDemographicsPostObservationTime  = TRUE,
    useDemographicsTimeInCohort         = TRUE,
    useConditionOccurrence              = TRUE,
    useProcedureOccurrence              = TRUE,
    useDrugEraStart                     = TRUE,
    useMeasurement                      = TRUE,
    useConditionEraStart                = TRUE,
    useConditionEraOverlap              = TRUE,
    useConditionEraGroupStart           = FALSE, # https://github.com/OHDSI/FeatureExtraction/issues/144
    useConditionEraGroupOverlap         = TRUE,
    useDrugExposure                     = FALSE, # too many concept IDs
    useDrugEraOverlap                   = FALSE,
    useDrugEraGroupStart                = FALSE, # https://github.com/OHDSI/FeatureExtraction/issues/144
    useDrugEraGroupOverlap              = TRUE,
    useObservation                      = TRUE,
    useVisitConceptCount                = TRUE,
    useVisitCount                       = TRUE,
    useDeviceExposure                   = TRUE,
    useCharlsonIndex                    = TRUE,
    useDcsi                             = TRUE,
    useChads2                           = TRUE,
    useChads2Vasc                       = TRUE,
    useHfrs                             = FALSE,
    temporalStartDays = c(
      -9999, # anytime prior
      -365, # long term prior
      -180, # medium term prior
      -30, # short term prior
      -365, # one year prior to -31
      -30, # 30 days prior, not including day 0
      0, # index date only
      1, # 1 day after to day 30
      31, # 31 days after to day 365
      -9999, # any time prior to any time future
      -30, # 30 days prior to 9999 days after
      -30, # 30 days prior to 365 days after
      -30, # 30 days prior to 180 days after
      -30  # 30 days prior to 30 days after
    ),
    temporalEndDays = c(
      0, # anytime prior
      0, # long term prior
      0, # medium term prior
      0, # short term prior
      -31, # one year prior to -31
      -1, # 30 days prior, not including day 0
      0, # index date only
      30, # 1 day after to day 30
      365, # 31 days after to day 365
      9999, # any time prior to any time future
      9999, # all after
      365,
      180,
      30
    )
  )

  # --- 3. point CohortDiagnostics at the derived cohort table ---------------
  cohortTableNames <- CohortGenerator::getCohortTableNames(cohortTable = cohortTableNew)

  # --- 4. run ----------------------------------------------------------------
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
    # concept-based diagnostics need real cohort JSON -> off for pre-built cohorts
    runInclusionStatistics        = FALSE,
    runIncludedSourceConcepts     = FALSE,
    runOrphanConcepts             = FALSE,
    runBreakdownIndexEvents       = FALSE,
    # these run off the generated cohort table -> keep on
    runVisitContext               = TRUE,
    runIncidenceRate              = TRUE,
    runTimeSeries                 = TRUE,
    runCohortRelationship         = TRUE,
    runTemporalCohortCharacterization = TRUE
  )
}
