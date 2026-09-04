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

# ------------------------------------------------------------------------------
# Private helpers
# ------------------------------------------------------------------------------

# Compute incidence rate + Poisson 95% CI for a single target-outcome pair.
# Returns a one-row data frame; suppresses IR/CI when n_events < minCellCount.
.calculateIR <- function(connection,
                         cohortDatabaseSchema,
                         cdmDatabaseSchema,
                         cohortTable,
                         targetId,
                         outcomeId,
                         outcomeName,
                         isEpisodic,
                         minCellCount,
                         dbms) {

  sqlFile <- if (isEpisodic) "getIRDataEpisodic.sql" else "getIRDataChronic.sql"

  sql <- SqlRender::readSql(
    system.file("sql", "sql_server", sqlFile, package = "PioneerBPA")
  )
  sql <- SqlRender::render(sql,
                           cohort_database_schema = cohortDatabaseSchema,
                           cdm_database_schema    = cdmDatabaseSchema,
                           cohort_table           = cohortTable,
                           target_id              = targetId,
                           outcome_id             = outcomeId
  )
  sql <- SqlRender::translate(sql, targetDialect = dbms)

  row <- DatabaseConnector::querySql(connection, sql, snakeCaseToCamelCase = TRUE)

  nPersons    <- row$nPersons
  nEvents     <- row$nEvents
  personYears <- row$personYears

  # Suppress small cell counts
  if (is.na(nEvents) || nEvents < minCellCount) {
    return(data.frame(
      targetId               = targetId,
      outcomeId              = outcomeId,
      outcomeName            = outcomeName,
      type                   = if (isEpisodic) "episodic" else "chronic",
      nPersons               = nPersons,
      nEvents                = NA_integer_,
      personYears            = NA_real_,
      incidenceRatePer1000Py = NA_real_,
      ci95Lb                 = NA_real_,
      ci95Ub                 = NA_real_,
      stringsAsFactors       = FALSE
    ))
  }

  ci <- survival::cipoisson(nEvents) / personYears

  data.frame(
    targetId               = targetId,
    outcomeId              = outcomeId,
    outcomeName            = outcomeName,
    type                   = if (isEpisodic) "episodic" else "chronic",
    nPersons               = nPersons,
    nEvents                = nEvents,
    personYears            = round(personYears, 2),
    incidenceRatePer1000Py = round(nEvents / personYears * 1000, 2),
    ci95Lb                 = round(ci[1] * 1000, 2),
    ci95Ub                 = round(ci[2] * 1000, 2),
    stringsAsFactors       = FALSE
  )
}

#' Run safety analysis
#'
#' Estimates the 3-year cumulative incidence of the study safety outcomes
#' (e.g. hospitalization, acute kidney injury, cardiovascular disease,
#' osteoporosis, chronic kidney disease, hypercalcemia, spinal cord
#' compression, bone fracture) using Kaplan-Meier survival analysis, and the
#' incidence rate (per 1,000 person-years, with 95\% Poisson CI) for each
#' outcome.
#'
#' The set of analyses is driven entirely by \code{inst/settings/IRsettings.csv}.
#' Each row of that file defines one target-cohort/outcome-cohort pair together
#' with its names and its episodic/chronic classification. All distinct target
#' cohorts found in the file are processed sequentially; for each target every
#' outcome listed against it is analysed. Chronic (new-onset) outcomes exclude
#' prevalent cases in both the KM and the incidence rate calculations.
#'
#' Individual-level time-to-event data is loaded into memory for computation
#' only and is never written to disk. All exported files contain aggregated
#' results only (KM survival table, 3-year point estimates, incidence rates),
#' each labelled with the target and outcome they belong to. Rows with fewer
#' than \code{minCellCount} events are suppressed.
#'
#' @param connectionDetails       DatabaseConnector connection details object.
#' @param cdmDatabaseSchema       Schema containing the OMOP CDM tables.
#' @param cohortDatabaseSchema    Schema where cohort tables are written.
#' @param cohortTable             Name of the cohort table.
#' @param databaseId              Short site identifier used to label outputs.
#' @param targetCohortIds         Optional integer vector restricting the run to
#'   a subset of target cohorts. \code{NULL} (default) runs every target cohort
#'   listed in \code{IRsettings.csv}.
#' @param outcomeCohortIds        Optional integer vector restricting the run to
#'   a subset of outcome cohorts. \code{NULL} (default) runs every outcome
#'   listed in \code{IRsettings.csv}.
#' @param minCellCount            Minimum number of events required to report a
#'   KM time point. Rows below this threshold are suppressed.
#' @param outputFolder            Path where result files will be written.
#'
#' @export
runIRandTTEAnalysis <- function(connectionDetails,
                                cdmDatabaseSchema,
                                cohortDatabaseSchema,
                                cohortTable,
                                databaseId,
                                targetCohortIds = NULL,
                                outcomeCohortIds = NULL,
                                minCellCount = 5,
                                outputFolder) {

  safetyFolder <- file.path(outputFolder, "IRandTTEAnalysis")
  if (!dir.exists(safetyFolder)) {
    dir.create(safetyFolder, recursive = TRUE)
  }

  # --------------------------------------------------------------------------
  # Analysis plan.
  #
  # IRsettings.csv is the single source of truth for which target x outcome
  # pairs to run. Columns:
  #   target_id, target_name, outcome_id, outcome_name, episodic, chronic
  # The chronic flag (chronic == 1) marks new-onset outcomes for which
  # prevalent cases are excluded in both the KM and the incidence rate
  # calculations. Target and outcome names are taken directly from this file.
  # --------------------------------------------------------------------------
  irSettings <- read.csv(
    system.file("settings", "IRsettings.csv", package = "PioneerBPA")
  )

  # Optional subsetting (default NULL = use everything in the file)
  if (!is.null(targetCohortIds)) {
    irSettings <- irSettings[irSettings$target_id %in% targetCohortIds, ]
  }
  if (!is.null(outcomeCohortIds)) {
    irSettings <- irSettings[irSettings$outcome_id %in% outcomeCohortIds, ]
  }

  # Drop rows with missing IDs
  irSettings <- irSettings[
    !is.na(irSettings$target_id) & !is.na(irSettings$outcome_id),
    ,
    drop = FALSE
  ]

  if (nrow(irSettings) == 0) {
    ParallelLogger::logWarn(
      "No target/outcome pairs to analyse after filtering IRsettings.csv."
    )
    return(invisible(NULL))
  }

  connection <- DatabaseConnector::connect(connectionDetails)
  on.exit(DatabaseConnector::disconnect(connection))
  dbms <- attr(connection, "dbms")

  # Containers for aggregated results across all targets and outcomes.
  # Keyed by position (not name) so repeated outcome names across different
  # targets do not overwrite one another.
  allKmTables <- list()
  allKm3Year  <- list()
  allIr       <- list()

  targetIds <- unique(irSettings$target_id)
  ParallelLogger::logInfo(
    "Safety analysis: ", length(targetIds), " target cohort(s) to process."
  )

  # --------------------------------------------------------------------------
  # Outer loop: target cohorts, processed sequentially
  # --------------------------------------------------------------------------
  for (targetCohortId in targetIds) {

    targetRows <- irSettings[irSettings$target_id == targetCohortId, , drop = FALSE]
    targetName <- as.character(targetRows$target_name[1])
    if (is.na(targetName) || !nzchar(targetName)) {
      targetName <- as.character(targetCohortId)
    }

    ParallelLogger::logInfo(
      "=== Target: ", targetName, " (cohort ", targetCohortId, ") \u2014 ",
      nrow(targetRows), " outcome(s) ==="
    )

    # ------------------------------------------------------------------------
    # Inner loop: outcomes listed for this target
    # ------------------------------------------------------------------------
    for (j in seq_len(nrow(targetRows))) {

      outcomeCohortId <- targetRows$outcome_id[j]
      outcomeName     <- as.character(targetRows$outcome_name[j])
      if (is.na(outcomeName) || !nzchar(outcomeName)) {
        outcomeName <- as.character(outcomeCohortId)
      }
      isChronic <- isTRUE(targetRows$chronic[j] == 1)

      ParallelLogger::logInfo(
        "  Outcome: ", outcomeName, " (cohort ", outcomeCohortId, ")"
      )

      # ----------------------------------------------------------------------
      # 1. Extract time-to-event data (individual level - memory only, not saved)
      #
      #    time_to_event : days from index to first outcome or censoring
      #    event         : 1 = outcome occurred, 0 = censored
      #
      #    Chronic (new-onset) outcomes use getTimeToEventChronic.sql, which
      #    excludes prevalent cases (outcome before cohort entry). Episodic
      #    outcomes use getTimeToEvent.sql, which keeps all subjects.
      #
      #    subject_id is used only for joining and is not retained in the result.
      # ----------------------------------------------------------------------
      sqlFile <- if (isChronic) "getTimeToEventChronic.sql" else "getTimeToEvent.sql"
      ParallelLogger::logInfo(
        "    time-to-event (",
        if (isChronic) "chronic, prevalent excluded" else "episodic",
        "): ", sqlFile
      )

      sql <- SqlRender::loadRenderTranslateSql(
        sqlFilename            = sqlFile,
        packageName            = "PioneerBPA",
        dbms                   = dbms,
        cohort_database_schema = cohortDatabaseSchema,
        cdm_database_schema    = cdmDatabaseSchema,
        cohort_table           = cohortTable,
        target_cohort_id       = targetCohortId,
        outcome_cohort_id      = outcomeCohortId
      )

      tteData <- DatabaseConnector::querySql(connection, sql, snakeCaseToCamelCase = TRUE)

      if (nrow(tteData) == 0) {
        ParallelLogger::logWarn(
          "    No data for ", targetName, " / ", outcomeName, " \u2014 skipping."
        )
        next
      }

      # ----------------------------------------------------------------------
      # 2. Kaplan-Meier
      # ----------------------------------------------------------------------
      kmFit <- survival::survfit(
        survival::Surv(timeToEvent, event) ~ 1,
        data = tteData
      )

      kmTable <- data.frame(
        time     = kmFit$time,
        n_risk   = kmFit$n.risk,
        n_event  = kmFit$n.event,
        n_censor = kmFit$n.censor,
        surv     = kmFit$surv,
        std_err  = kmFit$std.err,
        ci_lower = kmFit$lower,
        ci_upper = kmFit$upper
      )

      kmTable$targetId   <- targetCohortId
      kmTable$target     <- targetName
      kmTable$outcome    <- outcomeName
      kmTable$databaseId <- databaseId

      allKmTables[[length(allKmTables) + 1L]] <- kmTable

      # 3-year cumulative incidence point estimate
      idx3yr <- which(kmTable$time <= 1095)
      if (length(idx3yr) > 0) {
        lastIdx <- max(idx3yr)
        km3yr <- data.frame(
          targetId                 = targetCohortId,
          target                   = targetName,
          outcome                  = outcomeName,
          databaseId               = databaseId,
          surv_3yr                 = kmTable$surv[lastIdx],
          ci_lower_3yr             = kmTable$ci_lower[lastIdx],
          ci_upper_3yr             = kmTable$ci_upper[lastIdx],
          cumulative_incidence_3yr = 1 - kmTable$surv[lastIdx]
        )
      } else {
        km3yr <- data.frame(
          targetId                 = targetCohortId,
          target                   = targetName,
          outcome                  = outcomeName,
          databaseId               = databaseId,
          surv_3yr                 = NA,
          ci_lower_3yr             = NA,
          ci_upper_3yr             = NA,
          cumulative_incidence_3yr = NA
        )
      }
      allKm3Year[[length(allKm3Year) + 1L]] <- km3yr

      # ----------------------------------------------------------------------
      # 3. Incidence rate (per 1,000 person-years, 95% Poisson CI)
      #    Episodic outcomes count all events; chronic outcomes count first-onset
      #    among the outcome-naive population (prevalent cases excluded).
      # ----------------------------------------------------------------------
      irRow <- tryCatch(
        .calculateIR(
          connection           = connection,
          cohortDatabaseSchema = cohortDatabaseSchema,
          cdmDatabaseSchema    = cdmDatabaseSchema,
          cohortTable          = cohortTable,
          targetId             = targetCohortId,
          outcomeId            = outcomeCohortId,
          outcomeName          = outcomeName,
          isEpisodic           = !isChronic,
          minCellCount         = minCellCount,
          dbms                 = dbms
        ),
        error = function(e) {
          ParallelLogger::logError(
            "    Failed to compute IR for ", targetName, " / ", outcomeCohortId,
            ": ", conditionMessage(e)
          )
          NULL
        }
      )
      if (!is.null(irRow)) {
        irRow$target     <- targetName
        irRow$databaseId <- databaseId
        allIr[[length(allIr) + 1L]] <- irRow
      }

      # Individual-level tteData goes out of scope here and is not saved
      rm(tteData)
    }
  }

  # --------------------------------------------------------------------------
  # 4. Export aggregated results only
  # --------------------------------------------------------------------------
  if (length(allKmTables) > 0) {
    kmOut <- do.call(rbind, allKmTables)
    readr::write_excel_csv(kmOut, file.path(safetyFolder, "kmTable.csv"), na = "")
    ParallelLogger::logInfo("KM table written to kmTable.csv")
  }

  if (length(allKm3Year) > 0) {
    km3YearOut <- do.call(rbind, allKm3Year)
    readr::write_excel_csv(km3YearOut, file.path(safetyFolder, "km3YearEstimates.csv"), na = "")
    ParallelLogger::logInfo("3-year estimates written to km3YearEstimates.csv")
  }

  if (length(allIr) > 0) {
    irOut <- do.call(rbind, Filter(Negate(is.null), allIr))
    readr::write_excel_csv(irOut, file.path(safetyFolder, "incidenceRates.csv"), na = "")
    ParallelLogger::logInfo("Incidence rates written to incidenceRates.csv")
  }

  ParallelLogger::logInfo("Safety analysis complete. Results written to ", safetyFolder)
  invisible(NULL)
}
