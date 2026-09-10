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
# Private helpers (pure, unit-testable without a database)
# ------------------------------------------------------------------------------

# Decide whether the target vs comparator comparison is supportable from the
# propensity-score model. Returns list(comparable, reason).
#   - Both arms must have >= minCohortSize subjects (positivity of sample size).
#   - Empirical equipoise (fraction of subjects with preference score in
#     [0.3, 0.7]) must be >= equipoiseBound: enough overlap to compare.
#   - The PS-model AUC must not be extreme (<= aucBound): a near-perfect model
#     means the arms are almost separable, i.e. little overlap.
.assessComparability <- function(auc,
                                 equipoise,
                                 nTarget,
                                 nComparator,
                                 minCohortSize   = 100,
                                 equipoiseBound  = 0.25,
                                 aucBound        = 0.80) {
  if (nTarget < minCohortSize || nComparator < minCohortSize) {
    return(list(
      comparable = FALSE,
      reason = sprintf(
        "Insufficient sample size (target = %d, comparator = %d; minimum = %d per arm).",
        nTarget, nComparator, minCohortSize
      )
    ))
  }
  if (!is.na(equipoise) && equipoise < equipoiseBound) {
    return(list(
      comparable = FALSE,
      reason = sprintf(
        "Insufficient overlap: empirical equipoise %.3f < %.2f (few patients with comparable treatment probability).",
        equipoise, equipoiseBound
      )
    ))
  }
  if (!is.na(auc) && auc > aucBound) {
    return(list(
      comparable = FALSE,
      reason = sprintf(
        "Poor overlap: propensity-model AUC %.3f > %.2f (arms are nearly separable).",
        auc, aucBound
      )
    ))
  }
  list(
    comparable = TRUE,
    reason = sprintf(
      "Adequate sample size and overlap (target = %d, comparator = %d, AUC = %.3f, equipoise = %.3f).",
      nTarget, nComparator, ifelse(is.na(auc), NA_real_, auc),
      ifelse(is.na(equipoise), NA_real_, equipoise)
    )
  )
}

# Flag pairs of columns in a (dense) covariate matrix whose absolute Pearson
# correlation is >= threshold. Returns a data frame of flagged pairs. Pure and
# unit-testable; zero-variance columns are skipped.
.flagCorrelatedPairs <- function(covariateMatrix, threshold = 0.9) {
  empty <- data.frame(
    covariateId1 = numeric(0), covariateId2 = numeric(0),
    correlation  = numeric(0), stringsAsFactors = FALSE
  )
  if (is.null(covariateMatrix) || ncol(covariateMatrix) < 2) {
    return(empty)
  }
  sds <- apply(covariateMatrix, 2, stats::sd)
  keep <- which(is.finite(sds) & sds > 0)
  if (length(keep) < 2) {
    return(empty)
  }
  cm <- stats::cor(covariateMatrix[, keep, drop = FALSE])
  ids <- as.numeric(colnames(covariateMatrix)[keep])
  out <- empty
  for (i in seq_len(ncol(cm) - 1)) {
    for (j in (i + 1):ncol(cm)) {
      if (!is.na(cm[i, j]) && abs(cm[i, j]) >= threshold) {
        out <- rbind(out, data.frame(
          covariateId1 = ids[i], covariateId2 = ids[j],
          correlation  = cm[i, j], stringsAsFactors = FALSE
        ))
      }
    }
  }
  out
}

#' Run comparative effectiveness (denosumab vs zoledronic acid)
#'
#' Estimates the comparative effectiveness of denosumab (target) versus
#' zoledronic acid (comparator) for the study time-to-event outcomes, following
#' the OHDSI \pkg{CohortMethod} framework:
#' \enumerate{
#'   \item Baseline covariates are extracted with \pkg{FeatureExtraction},
#'     excluding the two exposure ingredients (and their descendants) so the
#'     treatment definition cannot leak into the propensity model.
#'   \item Propensity scores are estimated with a regularized (LASSO) logistic
#'     regression fit by \pkg{Cyclops} (\code{CohortMethod::createPs}).
#'   \item Patients are matched on the propensity score (default) or weighted by
#'     the inverse probability of treatment (\code{psMethod}).
#'   \item Each outcome is analysed with a Cox proportional-hazards model
#'     (stratified on the matched sets, or IPTW-weighted).
#' }
#'
#' Before any outcome model is fit, the function writes a \strong{propensity
#' score plot} and a \strong{comparability decision}: the comparison proceeds
#' only when the two arms are of sufficient size and have adequate overlap
#' (empirical equipoise and a non-extreme model AUC). When overlap is
#' inadequate the decision and plot are still written, but the outcome models are
#' skipped unless \code{forceIfNotComparable = TRUE}.
#'
#' If covariates are redundant or highly correlated - a common cause of unstable
#' or non-identifiable propensity models - the offending covariates are written
#' to \code{correlatedCovariates.csv} and logged (with names, ids, and the exact
#' \code{excludedCovariateConceptIds} value to set), so the user can exclude them
#' and re-run. A failure to fit the propensity model is caught and logged with
#' the same guidance rather than crashing the pipeline.
#'
#' The outcome set and the incident/recurrent (chronic) classification are read
#' from \code{inst/settings/IRsettings.csv}; chronic outcomes remove subjects
#' with the outcome prior to index. Only aggregated results are written to disk;
#' rows below \code{minCellCount} events are suppressed.
#'
#' @param connectionDetails       DatabaseConnector connection details object.
#' @param cdmDatabaseSchema       Schema containing the OMOP CDM tables.
#' @param cohortDatabaseSchema    Schema holding the cohort table.
#' @param cohortTable             Cohort table holding both the exposure arms and
#'   the outcome cohorts.
#' @param targetId                \code{cohort_definition_id} of the target
#'   (denosumab) arm. Default \code{90210}.
#' @param comparatorId            \code{cohort_definition_id} of the comparator
#'   (zoledronic acid) arm. Default \code{90220}.
#' @param outcomeIds              Optional integer vector of outcome cohort ids.
#'   \code{NULL} (default) uses every outcome in \code{IRsettings.csv}.
#' @param excludedCovariateConceptIds Concept ids of the exposure ingredients
#'   (denosumab and zoledronic acid) to exclude from the covariates, together
#'   with their descendants. \strong{Must be supplied}: an empty set lets the
#'   exposure leak into the propensity model and invalidates it (a warning is
#'   logged).
#' @param psMethod                Either \code{"matching"} (default) or
#'   \code{"weighting"} (stabilized IPTW).
#' @param riskWindowStart,riskWindowEnd Time-at-risk window in days relative to
#'   cohort start. Defaults \code{1} and \code{1095} (a 3-year window).
#' @param minCohortSize           Minimum subjects required per arm. Default 100.
#' @param minOutcomeEvents        Minimum events per arm to fit an outcome model.
#'   Default 10.
#' @param correlationThreshold    Absolute correlation at/above which a covariate
#'   pair is flagged. Default 0.9.
#' @param forceIfNotComparable    If \code{TRUE}, fit outcome models even when the
#'   comparability decision is negative. Default \code{FALSE}.
#' @param databaseId              Short site identifier used to label outputs.
#' @param minCellCount            Minimum event count to report (smaller counts
#'   are suppressed). Default 5.
#' @param outputFolder            Path where result files will be written.
#' @param packageName             Name of the package holding the settings.
#'
#' @export
runCohortMethodAnalysis <- function(connectionDetails,
                                    cdmDatabaseSchema,
                                    cohortDatabaseSchema,
                                    cohortTable,
                                    targetId = 90210,
                                    comparatorId = 90220,
                                    outcomeIds = NULL,
                                    excludedCovariateConceptIds = c(),
                                    psMethod = c("matching", "weighting"),
                                    riskWindowStart = 1,
                                    riskWindowEnd = 1095,
                                    minCohortSize = 100,
                                    minOutcomeEvents = 10,
                                    correlationThreshold = 0.9,
                                    forceIfNotComparable = FALSE,
                                    databaseId,
                                    minCellCount = 5,
                                    outputFolder,
                                    packageName = "PioneerBPA") {

  psMethod <- match.arg(psMethod)

  cmFolder <- file.path(outputFolder, "comparativeEffectiveness")
  if (!dir.exists(cmFolder)) {
    dir.create(cmFolder, recursive = TRUE)
  }

  # Small helper to persist the comparability decision and stop early.
  writeDecision <- function(comparable, reason) {
    decision <- data.frame(
      databaseId   = databaseId,
      targetId     = targetId,
      comparatorId = comparatorId,
      comparable   = comparable,
      reason       = reason,
      stringsAsFactors = FALSE
    )
    readr::write_excel_csv(
      decision, file.path(cmFolder, "comparabilityDecision.csv"), na = ""
    )
    decision
  }

  if (length(excludedCovariateConceptIds) == 0) {
    ParallelLogger::logWarn(
      "excludedCovariateConceptIds is empty: the denosumab and zoledronic acid ",
      "ingredient concepts (and descendants) should be excluded, otherwise the ",
      "exposure leaks into the propensity model and the AUC will approach 1."
    )
  }

  # --------------------------------------------------------------------------
  # Outcomes and chronic flag from IRsettings.csv
  # --------------------------------------------------------------------------
  irSettings <- read.csv(
    system.file("settings", "IRsettings.csv", package = packageName)
  )
  outcomeRef <- unique(
    irSettings[, c("outcome_id", "outcome_name", "chronic")]
  )
  outcomeRef <- outcomeRef[!is.na(outcomeRef$outcome_id), , drop = FALSE]
  if (!is.null(outcomeIds)) {
    outcomeRef <- outcomeRef[outcomeRef$outcome_id %in% outcomeIds, , drop = FALSE]
  }
  if (nrow(outcomeRef) == 0) {
    ParallelLogger::logWarn("No outcomes to analyse after filtering IRsettings.csv.")
    return(invisible(writeDecision(FALSE, "No outcomes selected.")))
  }
  allOutcomeIds <- as.numeric(outcomeRef$outcome_id)

  # --------------------------------------------------------------------------
  # 1. Extract CohortMethod data (baseline covariates, exposure ingredients
  #    excluded so the treatment cannot leak into the propensity model)
  # --------------------------------------------------------------------------
  ParallelLogger::logInfo(
    "Comparative effectiveness: target ", targetId, " vs comparator ",
    comparatorId, " (", psMethod, "); ", nrow(outcomeRef), " outcome(s)."
  )

  covariateSettings <- FeatureExtraction::createDefaultCovariateSettings(
    excludedCovariateConceptIds = excludedCovariateConceptIds,
    addDescendantsToExclude     = TRUE
  )

  cohortMethodData <- CohortMethod::getDbCohortMethodData(
    connectionDetails      = connectionDetails,
    cdmDatabaseSchema      = cdmDatabaseSchema,
    targetId               = targetId,
    comparatorId           = comparatorId,
    outcomeIds             = allOutcomeIds,
    exposureDatabaseSchema = cohortDatabaseSchema,
    exposureTable          = cohortTable,
    outcomeDatabaseSchema  = cohortDatabaseSchema,
    outcomeTable           = cohortTable,
    cdmVersion             = "5",
    covariateSettings      = covariateSettings
  )
  on.exit(Andromeda::close(cohortMethodData), add = TRUE)

  # --------------------------------------------------------------------------
  # 2. Sample-size guard
  # --------------------------------------------------------------------------
  cohorts <- dplyr::collect(cohortMethodData$cohorts)
  nTarget     <- sum(cohorts$treatment == 1)
  nComparator <- sum(cohorts$treatment == 0)
  ParallelLogger::logInfo(
    "Extracted ", nTarget, " target and ", nComparator, " comparator subjects."
  )
  if (nTarget < minCohortSize || nComparator < minCohortSize) {
    reason <- sprintf(
      "Insufficient sample size (target = %d, comparator = %d; minimum = %d per arm). Comparison not run.",
      nTarget, nComparator, minCohortSize
    )
    ParallelLogger::logWarn(reason)
    return(invisible(writeDecision(FALSE, reason)))
  }

  # --------------------------------------------------------------------------
  # 3. Redundant / correlated covariate screen (clear, actionable logging)
  # --------------------------------------------------------------------------
  covariateRef <- dplyr::collect(cohortMethodData$covariateRef)
  nameFor <- function(id) {
    nm <- covariateRef$covariateName[match(id, covariateRef$covariateId)]
    ifelse(is.na(nm), as.character(id), nm)
  }

  tidied <- tryCatch(
    FeatureExtraction::tidyCovariateData(cohortMethodData),
    error = function(e) {
      ParallelLogger::logWarn(
        "tidyCovariateData failed (", conditionMessage(e),
        "); continuing without the redundancy screen."
      )
      NULL
    }
  )
  redundantIds <- if (!is.null(tidied)) {
    attr(tidied, "metaData")$deletedRedundantCovariateIds
  } else NULL

  if (length(redundantIds) > 0) {
    redundantDf <- data.frame(
      covariateId   = redundantIds,
      covariateName = nameFor(redundantIds),
      reason        = "redundant/aliased (perfectly correlated within analysis)",
      stringsAsFactors = FALSE
    )
    readr::write_excel_csv(
      redundantDf, file.path(cmFolder, "correlatedCovariates.csv"), na = ""
    )
    ParallelLogger::logWarn(
      length(redundantIds), " redundant/correlated covariate(s) detected. ",
      "They are listed in correlatedCovariates.csv. To drop them from the ",
      "propensity model, add the corresponding concept ids to the ",
      "excludedCovariateConceptIds argument and re-run. Covariates: ",
      paste(utils::head(nameFor(redundantIds), 20), collapse = "; ")
    )
  } else {
    ParallelLogger::logInfo("No redundant/correlated covariates detected.")
  }

  # --------------------------------------------------------------------------
  # 4. Propensity score (LASSO logistic regression via Cyclops)
  # --------------------------------------------------------------------------
  psPopulation <- tryCatch(
    {
      pop <- CohortMethod::createStudyPopulation(
        cohortMethodData = cohortMethodData,
        outcomeId        = NULL,
        firstExposureOnly      = TRUE,
        restrictToCommonPeriod = TRUE,
        washoutPeriod          = 365,
        removeDuplicateSubjects = "keep first"
      )
      CohortMethod::createPs(cohortMethodData = cohortMethodData, population = pop)
    },
    error = function(e) {
      ParallelLogger::logError(
        "Failed to fit the propensity model: ", conditionMessage(e), ". ",
        "This is often caused by correlated / redundant / (near-)separating ",
        "covariates. Review correlatedCovariates.csv, add the offending ",
        "concept ids to excludedCovariateConceptIds, and re-run."
      )
      NULL
    }
  )
  if (is.null(psPopulation)) {
    return(invisible(writeDecision(FALSE, "Propensity model failed to fit (see log).")))
  }

  # --------------------------------------------------------------------------
  # 5. Propensity score plot + comparability decision
  # --------------------------------------------------------------------------
  psPlotFile <- file.path(
    cmFolder, sprintf("ps_%s_vs_%s.png", targetId, comparatorId)
  )
  tryCatch(
    CohortMethod::plotPs(
      data          = psPopulation,
      targetLabel   = paste("Target", targetId),
      comparatorLabel = paste("Comparator", comparatorId),
      fileName      = psPlotFile
    ),
    error = function(e) ParallelLogger::logWarn("plotPs failed: ", conditionMessage(e))
  )

  auc <- tryCatch(CohortMethod::computePsAuc(psPopulation),
                  error = function(e) NA_real_)
  auc <- as.numeric(auc)[1]
  equipoise <- tryCatch(CohortMethod::computeEquipoise(psPopulation),
                        error = function(e) NA_real_)

  metrics <- data.frame(
    databaseId   = databaseId,
    targetId     = targetId,
    comparatorId = comparatorId,
    nTarget      = nTarget,
    nComparator  = nComparator,
    psAuc        = round(auc, 4),
    equipoise    = round(as.numeric(equipoise), 4),
    stringsAsFactors = FALSE
  )
  readr::write_excel_csv(metrics, file.path(cmFolder, "psModelMetrics.csv"), na = "")

  assessment <- .assessComparability(
    auc = auc, equipoise = as.numeric(equipoise),
    nTarget = nTarget, nComparator = nComparator, minCohortSize = minCohortSize
  )
  writeDecision(assessment$comparable, assessment$reason)
  if (assessment$comparable) {
    ParallelLogger::logInfo("Comparability decision: SUPPORTED. ", assessment$reason)
  } else {
    ParallelLogger::logWarn("Comparability decision: NOT ADVISABLE. ", assessment$reason)
    if (!forceIfNotComparable) {
      ParallelLogger::logWarn(
        "Skipping outcome models (set forceIfNotComparable = TRUE to override). ",
        "Propensity plot and metrics have been written to ", cmFolder
      )
      return(invisible(NULL))
    }
  }

  # --------------------------------------------------------------------------
  # 6. Per-outcome Cox models (matching -> stratified Cox, IPTW -> weighted Cox)
  # --------------------------------------------------------------------------
  balanceList <- list()
  resultList  <- list()

  for (i in seq_len(nrow(outcomeRef))) {
    outcomeId   <- as.numeric(outcomeRef$outcome_id[i])
    outcomeName <- as.character(outcomeRef$outcome_name[i])
    isChronic   <- isTRUE(outcomeRef$chronic[i] == 1)

    ParallelLogger::logInfo(
      "  Outcome: ", outcomeName, " (", outcomeId, "; ",
      if (isChronic) "chronic, prior-outcome removed" else "recurrent", ")"
    )

    studyPop <- CohortMethod::createStudyPopulation(
      cohortMethodData        = cohortMethodData,
      population              = psPopulation,
      outcomeId               = outcomeId,
      firstExposureOnly       = TRUE,
      restrictToCommonPeriod  = TRUE,
      washoutPeriod           = 365,
      removeDuplicateSubjects = "keep first",
      removeSubjectsWithPriorOutcome = isChronic,
      minDaysAtRisk           = 1,
      riskWindowStart         = riskWindowStart,
      startAnchor             = "cohort start",
      riskWindowEnd           = riskWindowEnd,
      endAnchor               = "cohort start"
    )

    # Adjust (match or weight)
    adjPop <- tryCatch(
      if (psMethod == "matching") {
        CohortMethod::matchOnPs(
          population    = studyPop,
          caliper       = 0.2,
          caliperScale  = "standardized logit",
          maxRatio      = 1
        )
      } else {
        studyPop  # IPTW uses the PS directly in fitOutcomeModel
      },
      error = function(e) {
        ParallelLogger::logWarn("    Adjustment failed: ", conditionMessage(e))
        NULL
      }
    )
    if (is.null(adjPop) || nrow(adjPop) == 0) next

    # Event counts (per arm) and small-cell suppression
    nEventsTarget     <- sum(adjPop$outcomeCount > 0 & adjPop$treatment == 1)
    nEventsComparator <- sum(adjPop$outcomeCount > 0 & adjPop$treatment == 0)
    if (nEventsTarget < minOutcomeEvents || nEventsComparator < minOutcomeEvents) {
      ParallelLogger::logWarn(
        "    Too few events (target = ", nEventsTarget, ", comparator = ",
        nEventsComparator, "; minimum = ", minOutcomeEvents, "). Outcome skipped."
      )
      next
    }

    # Covariate balance (before/after adjustment)
    balance <- tryCatch(
      CohortMethod::computeCovariateBalance(population = adjPop, cohortMethodData = cohortMethodData),
      error = function(e) {
        ParallelLogger::logWarn("    computeCovariateBalance failed: ", conditionMessage(e))
        NULL
      }
    )
    if (!is.null(balance)) {
      tryCatch(
        CohortMethod::plotCovariateBalanceScatterPlot(
          balance  = balance,
          fileName = file.path(cmFolder, sprintf("covariateBalance_%s.png", outcomeId))
        ),
        error = function(e) ParallelLogger::logWarn("    balance plot failed: ", conditionMessage(e))
      )
      maxSdmAfter <- suppressWarnings(max(abs(balance$afterMatchingStdDiff), na.rm = TRUE))
      balance$outcomeId  <- outcomeId
      balance$databaseId <- databaseId
      balanceList[[length(balanceList) + 1L]] <- balance
    } else {
      maxSdmAfter <- NA_real_
    }

    # Cox proportional-hazards outcome model
    om <- tryCatch(
      CohortMethod::fitOutcomeModel(
        population        = adjPop,
        cohortMethodData  = cohortMethodData,
        modelType         = "cox",
        stratified        = (psMethod == "matching"),
        inversePtWeighting = (psMethod == "weighting")
      ),
      error = function(e) {
        ParallelLogger::logWarn("    fitOutcomeModel failed: ", conditionMessage(e))
        NULL
      }
    )
    if (is.null(om)) next

    est <- om$outcomeModelTreatmentEstimate
    resultList[[length(resultList) + 1L]] <- data.frame(
      databaseId        = databaseId,
      targetId          = targetId,
      comparatorId      = comparatorId,
      outcomeId         = outcomeId,
      outcomeName       = outcomeName,
      psMethod          = psMethod,
      nTarget           = sum(adjPop$treatment == 1),
      nComparator       = sum(adjPop$treatment == 0),
      eventsTarget      = nEventsTarget,
      eventsComparator  = nEventsComparator,
      hazardRatio       = round(exp(est$logRr), 3),
      ci95Lb            = round(exp(est$logLb95), 3),
      ci95Ub            = round(exp(est$logUb95), 3),
      logRr             = est$logRr,
      seLogRr           = est$seLogRr,
      maxAbsStdDiffAfter = round(maxSdmAfter, 3),
      stringsAsFactors  = FALSE
    )
  }

  # --------------------------------------------------------------------------
  # 7. Export aggregated results
  # --------------------------------------------------------------------------
  if (length(resultList) > 0) {
    results <- do.call(rbind, resultList)
    readr::write_excel_csv(results, file.path(cmFolder, "outcomeModelResults.csv"), na = "")
    ParallelLogger::logInfo("Outcome model results written to outcomeModelResults.csv")
  } else {
    ParallelLogger::logWarn("No outcome models produced (see log for reasons).")
  }
  if (length(balanceList) > 0) {
    balances <- do.call(rbind, balanceList)
    readr::write_excel_csv(balances, file.path(cmFolder, "covariateBalance.csv"), na = "")
  }

  ParallelLogger::logInfo("Comparative effectiveness analysis complete. Results in ", cmFolder)
  invisible(NULL)
}
