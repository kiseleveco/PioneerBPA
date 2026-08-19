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

#' Execute the PioneerBPA study
#'
#' Runs the full PioneerBPA analysis end to end. Each analytical step is
#' individually switchable so a site can (re)run just part of the study. The
#' steps run in the following order:
#' \enumerate{
#'   \item \strong{generateCohorts} - instantiate the study cohorts on the CDM
#'     with \code{\link{generateStudyCohorts}}.
#'   \item \strong{createTargetTable} - assemble the study target table with
#'     \code{\link{createTargetTable}}.
#'   \item \strong{createDerivedCohorts} - build the derived cohorts with
#'     \code{\link{createDerivedCohorts}}.
#'   \item \strong{runDiagnostics} - characterise the derived cohorts with
#'     \code{\link{runDerivedCohortDiagnostics}}.
#' }
#'
#' @param connectionDetails        DatabaseConnector connection details object.
#' @param cdmDatabaseSchema        Schema containing the OMOP CDM tables
#'   (read-only).
#' @param vocabularyDatabaseSchema Schema containing the vocabulary tables
#'   (typically the same as \code{cdmDatabaseSchema}).
#' @param cohortDatabaseSchema     Schema where cohort tables will be written
#'   (needs read / write / delete).
#' @param cohortTable              Base name for the cohort table populated by
#'   \code{\link{generateStudyCohorts}}.
#' @param cohortTableNew           Name of the derived cohort table.
#' @param targetTable              Name of the study target table.
#' @param outputFolder             Path where all result files will be written.
#' @param databaseId               Short database identifier (no spaces).
#' @param databaseName             Human-readable database name.
#' @param databaseDescription      Longer database description.
#' @param targetMetastasis         \code{cohort_definition_id} of the metastatic
#'   prostate cancer cohort.
#' @param targetBones              \code{cohort_definition_id} of the bone
#'   metastatic site cohort.
#' @param bpaZa                    \code{cohort_definition_id} of the zoledronic
#'   acid (ZA) cohort.
#' @param bpaDenosumab             \code{cohort_definition_id} of the denosumab
#'   cohort.
#' @param adt                      \code{cohort_definition_id} of the ADT cohort.
#' @param arpi                     \code{cohort_definition_id} of the ARPI cohort.
#' @param chemo                    \code{cohort_definition_id} of the
#'   chemotherapy cohort.
#' @param minCellCount             Minimum cell count for censoring small counts
#'   in the diagnostics output.
#' @param incrementalCohorts       Logical. Passed to
#'   \code{\link{generateStudyCohorts}} as \code{incremental}.
#' @param includeCohortStats       Logical. Passed to
#'   \code{\link{generateStudyCohorts}}.
#' @param generateCohorts          Logical. Run the cohort generation step.
#' @param createTargetTable        Logical. Run the target table step.
#' @param createDerivedCohorts     Logical. Run the derived cohort step.
#' @param runDiagnostics           Logical. Run the diagnostics step.
#' @param packageName              Name of this package.
#'
#' @export
execute <- function(connectionDetails,
                    cdmDatabaseSchema,
                    vocabularyDatabaseSchema = cdmDatabaseSchema,
                    cohortDatabaseSchema,
                    cohortTable,
                    cohortTableNew,
                    targetTable,
                    outputFolder,
                    databaseId,
                    databaseName        = databaseId,
                    databaseDescription = databaseId,
                    targetMetastasis,
                    targetBones,
                    bpaZa,
                    bpaDenosumab,
                    adt,
                    arpi,
                    chemo,
                    minCellCount           = 5,
                    incrementalCohorts     = TRUE,
                    includeCohortStats     = FALSE,
                    generateCohorts        = TRUE,
                    createTargetTable      = TRUE,
                    createDerivedCohorts   = TRUE,
                    runDiagnostics         = TRUE,
                    packageName            = "PioneerBPA") {

  if (!dir.exists(outputFolder)) {
    dir.create(outputFolder, recursive = TRUE)
  }

  # --------------------------------------------------------------------------
  # 1. Generate the study cohorts
  # --------------------------------------------------------------------------
  if (generateCohorts) {
    ParallelLogger::logInfo("Generating study cohorts")
    generateStudyCohorts(
      connectionDetails        = connectionDetails,
      cdmDatabaseSchema        = cdmDatabaseSchema,
      vocabularyDatabaseSchema = vocabularyDatabaseSchema,
      cohortDatabaseSchema     = cohortDatabaseSchema,
      cohortTable              = cohortTable,
      outputFolder             = outputFolder,
      incremental              = incrementalCohorts,
      includeCohortStats       = includeCohortStats
    )
  }

  # --------------------------------------------------------------------------
  # 2. Build the study target table (metastasis + bone + BPA + systemic tx)
  # --------------------------------------------------------------------------
  if (createTargetTable) {
    ParallelLogger::logInfo("Building study target table")
    PioneerBPA::createTargetTable(
      connectionDetails    = connectionDetails,
      cohortDatabaseSchema = cohortDatabaseSchema,
      cohortTable          = cohortTable,
      targetTable          = targetTable,
      targetMetastasis     = targetMetastasis,
      targetBones          = targetBones,
      bpaZa                = bpaZa,
      bpaDenosumab         = bpaDenosumab,
      adt                  = adt,
      arpi                 = arpi,
      chemo                = chemo,
      packageName          = packageName
    )
  }

  # --------------------------------------------------------------------------
  # 3. Build the derived cohorts
  # --------------------------------------------------------------------------
  if (createDerivedCohorts) {
    ParallelLogger::logInfo("Building derived cohorts")
    PioneerBPA::createDerivedCohorts(
      connectionDetails    = connectionDetails,
      cohortDatabaseSchema = cohortDatabaseSchema,
      targetTable          = targetTable,
      cohortTable          = cohortTable,
      cohortTableNew       = cohortTableNew,
      targetMetastasis     = targetMetastasis,
      packageName          = packageName
    )
  }

  # --------------------------------------------------------------------------
  # 4. Run CohortDiagnostics on the derived cohorts
  # --------------------------------------------------------------------------
  if (runDiagnostics) {
    ParallelLogger::logInfo("Running derived cohort diagnostics")
    runDerivedCohortDiagnostics(
      connectionDetails    = connectionDetails,
      cdmDatabaseSchema    = cdmDatabaseSchema,
      cohortDatabaseSchema = cohortDatabaseSchema,
      cohortTableNew       = cohortTableNew,
      exportFolder         = file.path(outputFolder, "diagnostics"),
      databaseId           = databaseId,
      databaseName         = databaseName,
      databaseDescription  = databaseDescription,
      vocabularyDatabaseSchema = vocabularyDatabaseSchema,
      minCellCount         = minCellCount,
      packageName          = packageName
    )
  }

  invisible(NULL)
}
