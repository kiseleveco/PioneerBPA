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

#' Build the study target table
#'
#' Assembles the study \code{targetTable} from the generated cohorts by running
#' three combination SQL scripts in sequence:
#' \enumerate{
#'   \item \code{metastasis_bone_combine.sql} - combines the metastatic
#'     prostate cancer cohort with the bone metastatic site cohort.
#'   \item \code{metastasis_bone_bpa_combine.sql} - layers on the bone
#'     protective agents (zoledronic acid and denosumab).
#'   \item \code{Systemic_treatment_join.sql} - joins on the systemic
#'     treatment cohorts (ADT, ARPI, chemotherapy).
#' }
#'
#' Each step opens its own database connection, loads and renders the SQL from
#' \code{inst/sql/sql_server/} with \code{SqlRender::loadRenderTranslateSql},
#' executes it, and disconnects. Cohort identifiers are supplied as the
#' \code{cohort_definition_id} values produced by \code{\link{generateStudyCohorts}}.
#'
#' @param connectionDetails    DatabaseConnector connection details object.
#' @param cohortDatabaseSchema Schema holding the cohort and target tables
#'   (needs read / write / delete).
#' @param cohortTable          Base name of the cohort table populated by
#'   \code{\link{generateStudyCohorts}}.
#' @param targetTable          Name of the target table to build.
#' @param targetMetastasis     \code{cohort_definition_id} of the metastatic
#'   prostate cancer cohort.
#' @param targetBones          \code{cohort_definition_id} of the bone
#'   metastatic site cohort.
#' @param bpaZa                \code{cohort_definition_id} of the zoledronic
#'   acid (ZA) cohort.
#' @param bpaDenosumab         \code{cohort_definition_id} of the denosumab
#'   cohort.
#' @param adt                  \code{cohort_definition_id} of the ADT cohort.
#' @param arpi                 \code{cohort_definition_id} of the ARPI cohort.
#' @param chemo                \code{cohort_definition_id} of the chemotherapy
#'   cohort.
#' @param packageName          Name of the package holding the SQL resources.
#'
#' @export
createTargetTable <- function(connectionDetails,
                              cohortDatabaseSchema,
                              cohortTable,
                              targetTable,
                              targetMetastasis,
                              targetBones,
                              bpaZa,
                              bpaDenosumab,
                              bpaAa,
                              bpaAll,
                              adt,
                              arpi,
                              chemo,
                              packageName = "PioneerBPA",
                              sensitivity = FALSE) {

  # Each step opens its own connection, loads and renders the SQL, executes it,
  # and disconnects. Parameters common to every step are captured from the
  # enclosing scope; only the SQL file name and the step-specific cohort ids
  # (passed via `...`) differ between calls.
  runStep <- function(sqlFilename, ...) {
    connection <- DatabaseConnector::connect(connectionDetails)
    on.exit(DatabaseConnector::disconnect(connection))
    sql <- SqlRender::loadRenderTranslateSql(
      sqlFilename            = sqlFilename,
      packageName            = packageName,
      dbms                   = attr(connection, "dbms"),
      cohort_database_schema = cohortDatabaseSchema,
      cohort_table           = cohortTable,
      target_table           = targetTable,
      ...
    )
    DatabaseConnector::executeSql(connection, sql)
  }

  ## Combine metastasis + bone
  runStep("metastasis_bone_combine.sql",
          target_metastasis = targetMetastasis,
          target_bones      = targetBones)

  ## Combine metastasis + bone + BPA
  if (sensitivity) {
    runStep("metastasis_bone_bpa_sensitivity_combine.sql",
            bpa_za        = bpaZa,
            bpa_denosumab = bpaDenosumab,
            bpa_aa        = bpaAa,
            bpa_all       = bpaAll)
  } else {
    runStep("metastasis_bone_bpa_combine.sql",
            bpa_za        = bpaZa,
            bpa_denosumab = bpaDenosumab)
  }

  ## Combine metastasis + bone + BPA + systemic treatment
  runStep("Systemic_treatment_join.sql",
          cohort_adt   = adt,
          cohort_arpi  = arpi,
          cohort_chemo = chemo)

  invisible(NULL)
}
