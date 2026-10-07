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

# Summarise a vector of day counts: n, mean with a t-based 95% CI of the mean,
# SD, median and the interquartile range (Q1, Q3, IQR). Pure and unit-testable.
# Returns a one-row data frame; every statistic is NA when there are fewer than
# minCellCount individuals (small-cell suppression, n included). The CI needs
# n >= 2. Min / max are deliberately not reported (they are individual values).
.summariseDays <- function(x, minCellCount = 5) {
  x <- x[!is.na(x)]
  n <- length(x)
  out <- data.frame(
    nIndividuals = NA_integer_, meanDays = NA_real_, ci95Lb = NA_real_,
    ci95Ub = NA_real_, sdDays = NA_real_, medianDays = NA_real_,
    q1Days = NA_real_, q3Days = NA_real_, iqrDays = NA_real_
  )
  if (n == 0 || n < minCellCount) {
    return(out)
  }
  m  <- mean(x)
  s  <- stats::sd(x)
  q  <- stats::quantile(x, probs = c(0.25, 0.5, 0.75), names = FALSE)
  hw <- if (n >= 2) stats::qt(0.975, df = n - 1) * s / sqrt(n) else NA_real_
  out$nIndividuals <- n
  out$meanDays     <- round(m, 1)
  out$ci95Lb       <- round(m - hw, 1)
  out$ci95Ub       <- round(m + hw, 1)
  out$sdDays       <- round(s, 1)
  out$medianDays   <- round(q[2], 1)
  out$q1Days       <- round(q[1], 1)
  out$q3Days       <- round(q[3], 1)
  out$iqrDays      <- round(q[3] - q[1], 1)
  out
}

#' Run treatment-pattern and drug-switch analysis
#'
#' For each bone-protective-agent arm - denosumab (90210) and zoledronic acid
#' (90220) - reconstructs each subject's dosing timeline from the individual
#' administration events (cohorts 1771 / 1770) and splits it into continuous
#' treatment episodes labelled by dosing-interval band. An episode is a maximal
#' run of consecutive administrations whose gaps all fall in the SAME band, so
#' different regimens (e.g. 3-5 weeks vs 11-13 weeks) are never merged. The dose
#' at a band change is shared by the two adjacent episodes.
#'
#' Bands: denosumab = every 3-5 weeks or 4-7 months; ZA = every 3-5 weeks,
#' 11-13 weeks, or 10-13 months. A gap outside every band ends the episode.
#'
#' The regimen output has, per arm, one row per band plus two summary rows:
#' \code{ALL} (mean index -> last-dose span and dose count over every arm
#' member) and \code{NO_REGIMEN} (the same over members with no band episode).
#' A separate output detects switches to the other agent occurring more than
#' \code{graceDays} after the index date.
#'
#' It also summarises the time from the bone-metastasis date (start of cohort
#' 90100) to the first BPA administration (start of cohort 90200), overall and
#' by first agent: number of individuals, mean with a t-based 95\% confidence
#' interval, SD, median and interquartile range (Q1, Q3, IQR), written to
#' \code{timeToFirstBpa.csv}. Values can be negative, because the BPA window
#' opens 30 days before the bone-metastasis date.
#'
#' Only aggregated results are written; rows with fewer than \code{minCellCount}
#' individuals are suppressed.
#'
#' @param connectionDetails    DatabaseConnector connection details object.
#' @param cohortDatabaseSchema Schema holding the cohort tables.
#' @param drugCohortTable      Table with the administration events (1770/1771).
#' @param armCohortTable       Table with the arm cohorts (90210/90220).
#' @param databaseId           Short site identifier used to label outputs.
#' @param outputFolder         Path where result files are written.
#' @param graceDays            Days after index before an other-agent dose counts
#'   as a switch. Default 30.
#' @param monthDays            Days per month for month-band conversion.
#'   Default 30.44.
#' @param minCellCount         Minimum individuals to report a row. Default 5.
#' @param packageName          Name of the package holding the SQL resources.
#'
#' @export
runTreatmentPatternAnalysis <- function(connectionDetails,
                                        cohortDatabaseSchema,
                                        drugCohortTable = "cohortBPA",
                                        armCohortTable  = "cohortTableNew",
                                        databaseId,
                                        outputFolder,
                                        graceDays    = 30,
                                        monthDays    = 30.44,
                                        minCellCount = 5,
                                        packageName  = "PioneerBPA") {

  tpFolder <- file.path(outputFolder, "treatmentPatterns")
  if (!dir.exists(tpFolder)) {
    dir.create(tpFolder, recursive = TRUE)
  }

  wk <- function(w) round(w * 7)
  mo <- function(m) round(m * monthDays)

  # Arm configuration: regimen drug, switch-to drug, and interval bands (days).
  # Denosumab has 2 bands, so its 3rd band is an impossible range (never matches).
  arms <- list(
    list(targetId = 90210, drugId = 1771, switchDrugId = 1770, label = "Denosumab (90210)",
         bands = list(
           list(lo = wk(3), hi = wk(5), label = "deno_3_5w"),
           list(lo = mo(4), hi = mo(7), label = "deno_4_7m"),
           list(lo = 999999, hi = 999999, label = "unused")
         )),
    list(targetId = 90220, drugId = 1770, switchDrugId = 1771, label = "ZA (90220)",
         bands = list(
           list(lo = wk(3),  hi = wk(5),  label = "za_3_5w"),
           list(lo = wk(11), hi = wk(13), label = "za_11_13w"),
           list(lo = mo(10), hi = mo(13), label = "za_10_13m")
         ))
  )

  connection <- DatabaseConnector::connect(connectionDetails)
  on.exit(DatabaseConnector::disconnect(connection))
  dbms <- attr(connection, "dbms")

  regimenRows <- list()
  switchRows  <- list()

  for (arm in arms) {
    ParallelLogger::logInfo("Treatment patterns: ", arm$label)
    b <- arm$bands

    # ------------------------------------------------------------------------
    # 1. Continuous-exposure episodes (banded runs)
    # ------------------------------------------------------------------------
    episodesSql <- SqlRender::loadRenderTranslateSql(
      sqlFilename            = "treatmentPatternEpisodes.sql",
      packageName            = packageName,
      dbms                   = dbms,
      cohort_database_schema = cohortDatabaseSchema,
      drug_cohort_table      = drugCohortTable,
      arm_cohort_table       = armCohortTable,
      target_cohort_id       = arm$targetId,
      drug_cohort_id         = arm$drugId,
      band1_lo = b[[1]]$lo, band1_hi = b[[1]]$hi, band1_label = b[[1]]$label,
      band2_lo = b[[2]]$lo, band2_hi = b[[2]]$hi, band2_label = b[[2]]$label,
      band3_lo = b[[3]]$lo, band3_hi = b[[3]]$hi, band3_label = b[[3]]$label
    )
    episodes <- DatabaseConnector::querySql(connection, episodesSql, snakeCaseToCamelCase = TRUE)

    # ------------------------------------------------------------------------
    # 2. Per-subject rollup (for ALL / NO_REGIMEN)
    # ------------------------------------------------------------------------
    subjectsSql <- SqlRender::loadRenderTranslateSql(
      sqlFilename            = "treatmentPatternSubjects.sql",
      packageName            = packageName,
      dbms                   = dbms,
      cohort_database_schema = cohortDatabaseSchema,
      drug_cohort_table      = drugCohortTable,
      arm_cohort_table       = armCohortTable,
      target_cohort_id       = arm$targetId,
      drug_cohort_id         = arm$drugId
    )
    subjects <- DatabaseConnector::querySql(connection, subjectsSql, snakeCaseToCamelCase = TRUE)

    # ------------------------------------------------------------------------
    # 3. Switch to the other agent
    # ------------------------------------------------------------------------
    switchSql <- SqlRender::loadRenderTranslateSql(
      sqlFilename            = "treatmentSwitch.sql",
      packageName            = packageName,
      dbms                   = dbms,
      cohort_database_schema = cohortDatabaseSchema,
      drug_cohort_table      = drugCohortTable,
      arm_cohort_table       = armCohortTable,
      target_cohort_id       = arm$targetId,
      switch_drug_cohort_id  = arm$switchDrugId,
      grace_days             = graceDays
    )
    switched <- DatabaseConnector::querySql(connection, switchSql, snakeCaseToCamelCase = TRUE)

    # ------------------------------------------------------------------------
    # 4. Aggregate: one row per band regimen
    # ------------------------------------------------------------------------
    if (nrow(episodes) > 0) {
      byReg <- dplyr::summarise(
        dplyr::group_by(episodes, regimen),
        nIndividuals  = dplyr::n_distinct(subjectId),
        nEpisodes     = dplyr::n(),
        avgLengthDays = mean(lengthDays),
        avgNDoses     = mean(nDoses),
        .groups = "drop"
      )
      byReg <- as.data.frame(byReg)
    } else {
      byReg <- data.frame(
        regimen = character(0), nIndividuals = integer(0), nEpisodes = integer(0),
        avgLengthDays = numeric(0), avgNDoses = numeric(0), stringsAsFactors = FALSE
      )
    }
    regimenSubjects <- unique(episodes$subjectId)

    # ALL row: every arm member (index -> last-dose span, total doses)
    allRow <- data.frame(
      regimen = "ALL",
      nIndividuals  = nrow(subjects),
      nEpisodes     = NA_integer_,
      avgLengthDays = if (nrow(subjects) > 0) mean(subjects$daysStartToLast) else NA_real_,
      avgNDoses     = if (nrow(subjects) > 0) mean(subjects$nDoses)          else NA_real_,
      stringsAsFactors = FALSE
    )

    # NO_REGIMEN row: members with no band episode
    noReg <- subjects[!subjects$subjectId %in% regimenSubjects, , drop = FALSE]
    noRegRow <- data.frame(
      regimen = "NO_REGIMEN",
      nIndividuals  = nrow(noReg),
      nEpisodes     = NA_integer_,
      avgLengthDays = if (nrow(noReg) > 0) mean(noReg$daysStartToLast) else NA_real_,
      avgNDoses     = if (nrow(noReg) > 0) mean(noReg$nDoses)          else NA_real_,
      stringsAsFactors = FALSE
    )

    armReg <- rbind(byReg, allRow, noRegRow)
    armReg$databaseId <- databaseId
    armReg$cohortId   <- arm$targetId
    armReg$arm        <- arm$label
    regimenRows[[length(regimenRows) + 1L]] <- armReg

    # ------------------------------------------------------------------------
    # 5. Aggregate: switch summary row
    # ------------------------------------------------------------------------
    nArm    <- nrow(subjects)
    nSwitch <- length(unique(switched$subjectId))
    switchRows[[length(switchRows) + 1L]] <- data.frame(
      databaseId       = databaseId,
      cohortId         = arm$targetId,
      arm              = arm$label,
      switchToCohortId = arm$switchDrugId,
      nArm             = nArm,
      nSwitchers       = nSwitch,
      pctSwitchers     = if (nArm > 0)    round(100 * nSwitch / nArm, 2)     else NA_real_,
      avgDaysToSwitch  = if (nSwitch > 0) round(mean(switched$daysToSwitch), 1) else NA_real_,
      stringsAsFactors = FALSE
    )
  }

  regimens <- do.call(rbind, regimenRows)
  switches <- do.call(rbind, switchRows)

  # --------------------------------------------------------------------------
  # 5b. Time from the bone-metastasis date to the first BPA administration
  #     (index cohort 90100 -> any-BPA cohort 90200), overall and by first agent.
  #     Individual-level days are held in memory only; only summaries are saved.
  # --------------------------------------------------------------------------
  timeSql <- SqlRender::loadRenderTranslateSql(
    sqlFilename            = "timeToFirstBpa.sql",
    packageName            = packageName,
    dbms                   = dbms,
    cohort_database_schema = cohortDatabaseSchema,
    arm_cohort_table       = armCohortTable,
    bone_cohort_id         = 90100,
    bpa_cohort_id          = 90200,
    deno_cohort_id         = 90210,
    za_cohort_id           = 90220
  )
  timeData <- DatabaseConnector::querySql(connection, timeSql, snakeCaseToCamelCase = TRUE)

  timeGroups <- list(
    "Any BPA"           = timeData$daysToFirstBpa,
    "Denosumab first"   = timeData$daysToFirstBpa[timeData$firstAgent == "Denosumab"],
    "ZA first"          = timeData$daysToFirstBpa[timeData$firstAgent == "ZA"]
  )
  timeToBpa <- do.call(rbind, lapply(names(timeGroups), function(g) {
    cbind(
      data.frame(databaseId = databaseId, group = g, stringsAsFactors = FALSE),
      .summariseDays(timeGroups[[g]], minCellCount)
    )
  }))
  rm(timeData, timeGroups)

  # --------------------------------------------------------------------------
  # 6. Small-cell suppression and export
  # --------------------------------------------------------------------------
  supp <- !is.na(regimens$nIndividuals) & regimens$nIndividuals < minCellCount
  regimens$avgLengthDays[supp] <- NA
  regimens$avgNDoses[supp]     <- NA
  regimens$nIndividuals[supp]  <- NA
  regimens$avgLengthDays <- round(regimens$avgLengthDays, 1)
  regimens$avgNDoses     <- round(regimens$avgNDoses, 2)

  switchSupp <- !is.na(switches$nSwitchers) & switches$nSwitchers < minCellCount
  switches$nSwitchers[switchSupp]      <- NA
  switches$pctSwitchers[switchSupp]    <- NA
  switches$avgDaysToSwitch[switchSupp] <- NA

  readr::write_excel_csv(regimens, file.path(tpFolder, "treatmentPatternRegimens.csv"), na = "")
  readr::write_excel_csv(switches, file.path(tpFolder, "treatmentSwitch.csv"), na = "")
  readr::write_excel_csv(timeToBpa, file.path(tpFolder, "timeToFirstBpa.csv"), na = "")

  ParallelLogger::logInfo("Treatment-pattern results written to ", tpFolder)
  invisible(NULL)
}
