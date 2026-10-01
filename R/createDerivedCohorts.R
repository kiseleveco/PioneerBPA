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

#' Build the derived study cohorts
#'
#' Populates the derived cohort table (\code{cohortTableNew}) by running the
#' sequence of derivation SQL scripts from \code{inst/sql/sql_server/}. These
#' scripts build the index, BPA / no-BPA populations, and the treatment
#' combination cohorts (see \code{inst/settings/DerivedCohorts.csv} for the
#' resulting \code{cohort_definition_id} values and their descriptions).
#'
#' The list of derived cohort ids is read from
#' \code{inst/settings/DerivedCohorts.csv} (in file order), so it stays in sync
#' with the study specification. The \code{cohort_src} script builds a temporary
#' source table consumed by every derivation script; it is not a cohort and is
#' not listed in the CSV, so it is always run first.
#'
#' A connection may be supplied via \code{connection}; otherwise one is opened
#' from \code{connectionDetails} and closed on exit.
#'
#' @param connectionDetails    DatabaseConnector connection details object.
#'   Ignored when \code{connection} is supplied.
#' @param connection           An optional open DatabaseConnector connection.
#'   When \code{NULL} a connection is opened from \code{connectionDetails} and
#'   disconnected on exit.
#' @param cohortDatabaseSchema Schema holding the cohort, target, and derived
#'   cohort tables.
#' @param targetTable          Name of the study target table built by
#'   \code{\link{createTargetTable}}.
#' @param cohortTable          Base name of the cohort table populated by
#'   \code{\link{generateStudyCohorts}}.
#' @param cohortTableNew       Name of the derived cohort table to populate.
#' @param targetMetastasis     \code{cohort_definition_id} of the metastatic
#'   prostate cancer cohort.
#' @param packageName          Name of the package holding the SQL resources.
#' @param createTable          Logical. If \code{TRUE}, create the derived
#'   cohort table via \code{\link{createCohortTableNew}} when it does not exist.
#' @param deleteExisting       Logical. If \code{TRUE}, delete any existing rows
#'   for the derived \code{cohort_definition_id} values before re-populating.
#'
#' @export
createDerivedCohorts <- function(connectionDetails = NULL,
                                 connection = NULL,
                                 cohortDatabaseSchema,
                                 targetTable,
                                 cohortTable,
                                 cohortTableNew,
                                 targetMetastasis,
                                 packageName    = "PioneerBPA",
                                 createTable    = TRUE,
                                 deleteExisting = TRUE) {

  # Derived cohort ids are read from inst/settings/DerivedCohorts.csv, in file
  # order, so the list stays in sync with the study specification. "cohort_src"
  # builds a temporary source table consumed by every derivation script; it is
  # not a cohort and is not listed in the CSV, so prepend it explicitly.
  csvPath <- system.file("settings", "DerivedCohorts.csv", package = packageName)
  derivedCohorts <- read.csv(csvPath, stringsAsFactors = FALSE)
  sqlFiles <- c("cohort_src", as.character(derivedCohorts$cohortId))

  if (is.null(connection)) {
    connection <- DatabaseConnector::connect(connectionDetails)
    on.exit(DatabaseConnector::disconnect(connection))
  }

  # Create the target table if it isn't there yet (never drops an existing one).
  if (createTable) {
    createCohortTableNew(connection, cohortDatabaseSchema, cohortTableNew)
  }

  if (deleteExisting) {
    cohortIds <- as.integer(setdiff(sqlFiles, "cohort_src"))
    sql <- SqlRender::render("DELETE FROM @schema.@table WHERE cohort_definition_id IN (@ids);",
                             schema = cohortDatabaseSchema,
                             table  = cohortTableNew,
                             ids    = cohortIds)
    sql <- SqlRender::translate(sql, targetDialect = connection@dbms)
    DatabaseConnector::executeSql(connection, sql)
  }

  for (f in sqlFiles) {
    message("Running ", f, ".sql")
    sql <- SqlRender::loadRenderTranslateSql(
      sqlFilename            = paste0(f, ".sql"),
      packageName            = packageName,
      dbms                   = connection@dbms,
      cohort_database_schema = cohortDatabaseSchema,
      target_table           = targetTable,
      cohort_table           = cohortTable,
      cohortTableNew         = cohortTableNew,
      target_metastasis      = targetMetastasis
    )
    tryCatch(
      DatabaseConnector::executeSql(connection, sql),
      error = function(e) stop("Failed on ", f, ".sql: ", conditionMessage(e))
    )
  }

  invisible(NULL)
}
