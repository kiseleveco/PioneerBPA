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

#' Run the isolated sensitivity cohort analysis
#'
#' Builds an \strong{independent}, fully isolated set of sensitivity derived
#' cohorts and reports their counts. Nothing is shared with the main workflow:
#' it assembles its own sensitivity target table (\code{targetTableSensitivity})
#' with the four BPA arms (ZA / denosumab / AA / other-BPA) via
#' \code{\link{createTargetTable}} with \code{sensitivity = TRUE}, stages it with
#' \code{cohort_src_sensitivity.sql}, and writes the sensitivity cohorts to their
#' own derived table (\code{cohortTableSensitivity}). The main \code{targetTable}
#' and \code{cohortTableNew} are never touched.
#'
#' The sensitivity cohort set (read from
#' \code{inst/settings/DerivedCohortsSensitivity.csv}) is:
#' \itemize{
#'   \item 90100 - bone-metastasis index
#'   \item 90200 - any BPA (ZA / denosumab / AA)
#'   \item 90300 - no BPA (no ZA, no denosumab) with systemic treatment
#'   \item 90400 - no ANY BPA, with systemic treatment (index = systemic start)
#'   \item 90210 / 90220 / 90230 / 90240 - denosumab / ZA / AA / other-BPA arms
#' }
#' Only the cohort counts are reported, to
#' \code{outputFolder/sensitivity/sensitivityCohortCounts.csv}; counts below
#' \code{minCellCount} are suppressed.
#'
#' @param connectionDetails        DatabaseConnector connection details object.
#' @param cohortDatabaseSchema     Schema holding the cohort and target tables.
#' @param cohortTable              Base cohort table with the generated cohorts
#'   (metastasis, bone, ZA, denosumab, AA, other-BPA, ADT, ARPI, chemo).
#' @param targetTableSensitivity   Name of the isolated sensitivity target table.
#' @param cohortTableSensitivity   Name of the isolated sensitivity derived
#'   cohort table.
#' @param targetMetastasis,targetBones \code{cohort_definition_id}s of the
#'   metastasis and bone cohorts.
#' @param bpaZa,bpaDenosumab,bpaAa,bpaAll \code{cohort_definition_id}s of the
#'   ZA, denosumab, AA, and other-BPA (broad) cohorts.
#' @param adt,arpi,chemo           \code{cohort_definition_id}s of the systemic
#'   treatment cohorts.
#' @param databaseId               Short site identifier used to label outputs.
#' @param outputFolder             Path where result files are written.
#' @param minCellCount             Minimum count to report. Default 5.
#' @param packageName              Name of the package holding the SQL/settings.
#'
#' @export
runSensitivityAnalysis <- function(connectionDetails,
                                   cohortDatabaseSchema,
                                   cohortTable,
                                   targetTableSensitivity = "targetTableSensitivity",
                                   cohortTableSensitivity = "cohortTableNewSensitivity",
                                   targetMetastasis,
                                   targetBones,
                                   bpaZa,
                                   bpaDenosumab,
                                   bpaAa,
                                   bpaAll,
                                   adt,
                                   arpi,
                                   chemo,
                                   databaseId,
                                   outputFolder,
                                   minCellCount = 5,
                                   packageName  = "PioneerBPA") {

  if (is.null(bpaAa) || is.null(bpaAll)) {
    ParallelLogger::logWarn(
      "Sensitivity analysis needs bpaAa and bpaAll cohort ids; one is NULL - skipping."
    )
    return(invisible(NULL))
  }

  sensFolder <- file.path(outputFolder, "sensitivity")
  if (!dir.exists(sensFolder)) {
    dir.create(sensFolder, recursive = TRUE)
  }

  # --------------------------------------------------------------------------
  # 1. Build the ISOLATED sensitivity target table (ZA/denosumab/AA/other arms)
  # --------------------------------------------------------------------------
  ParallelLogger::logInfo("Sensitivity: building isolated target table ", targetTableSensitivity)
  createTargetTable(
    connectionDetails    = connectionDetails,
    cohortDatabaseSchema = cohortDatabaseSchema,
    cohortTable          = cohortTable,
    targetTable          = targetTableSensitivity,
    targetMetastasis     = targetMetastasis,
    targetBones          = targetBones,
    bpaZa                = bpaZa,
    bpaDenosumab         = bpaDenosumab,
    bpaAa                = bpaAa,
    bpaAll               = bpaAll,
    adt                  = adt,
    arpi                 = arpi,
    chemo                = chemo,
    packageName          = packageName,
    sensitivity          = TRUE
  )

  # --------------------------------------------------------------------------
  # 2. Build the ISOLATED sensitivity derived cohorts
  # --------------------------------------------------------------------------
  cohorts <- read.csv(
    system.file("settings", "DerivedCohortsSensitivity.csv", package = packageName),
    stringsAsFactors = FALSE
  )
  sqlFiles <- paste0(as.character(cohorts$cohortId), "s")  # 90100s, 90200s, ...

  connection <- DatabaseConnector::connect(connectionDetails)
  on.exit(DatabaseConnector::disconnect(connection))

  # Fresh, isolated derived cohort table (drop-and-recreate)
  createCohortTableNew(connection, cohortDatabaseSchema, cohortTableSensitivity)

  # Sensitivity staging table (#cohort_src) from the sensitivity target table
  ParallelLogger::logInfo("Sensitivity: staging cohort_src_sensitivity")
  srcSql <- SqlRender::loadRenderTranslateSql(
    sqlFilename            = "cohort_src_sensitivity.sql",
    packageName            = packageName,
    dbms                   = connection@dbms,
    cohort_database_schema = cohortDatabaseSchema,
    target_table           = targetTableSensitivity
  )
  DatabaseConnector::executeSql(connection, srcSql)

  for (f in sqlFiles) {
    ParallelLogger::logInfo("Sensitivity: running ", f, ".sql")
    sql <- SqlRender::loadRenderTranslateSql(
      sqlFilename            = paste0(f, ".sql"),
      packageName            = packageName,
      dbms                   = connection@dbms,
      cohort_database_schema = cohortDatabaseSchema,
      cohort_table           = cohortTable,
      cohortTableNew         = cohortTableSensitivity,
      target_metastasis      = targetMetastasis
    )
    tryCatch(
      DatabaseConnector::executeSql(connection, sql),
      error = function(e) stop("Failed on ", f, ".sql: ", conditionMessage(e))
    )
  }

  # --------------------------------------------------------------------------
  # 3. Report the cohort counts
  # --------------------------------------------------------------------------
  counts <- CohortGenerator::getCohortCounts(
    connection           = connection,
    cohortDatabaseSchema = cohortDatabaseSchema,
    cohortTable          = cohortTableSensitivity
  )

  # Attach names and label with the database id
  report <- merge(
    data.frame(cohortId = as.double(cohorts$cohortId),
               cohortName = cohorts$cohortName, stringsAsFactors = FALSE),
    counts, by = "cohortId", all.x = TRUE
  )
  report$databaseId <- databaseId
  report <- report[order(report$cohortId), ]

  # Small-cell suppression
  countCols <- intersect(c("cohortEntries", "cohortSubjects"), names(report))
  for (col in countCols) {
    report[[col]][!is.na(report[[col]]) & report[[col]] < minCellCount] <- NA
  }

  readr::write_excel_csv(
    report, file.path(sensFolder, "sensitivityCohortCounts.csv"), na = ""
  )
  ParallelLogger::logInfo("Sensitivity cohort counts written to ",
                          file.path(sensFolder, "sensitivityCohortCounts.csv"))

  invisible(report)
}
