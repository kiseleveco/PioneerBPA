# PioneerBPA

Real-world utilization of Bone Protective Agents in metastatic prostate cancer

- **Analytics use case(s):** Characterization
- **Study type:** Clinical Application
- **Tags:** Prostate cancer, Bone metastases, Bone protective agents
- **Data model:** OMOP CDM v5.x
- **Study package status:** In development

## Introduction

`PioneerBPA` is an OHDSI ([HADES](https://ohdsi.github.io/Hades/)) study package that
describes the real-world utilization of **bone protective agents (BPA)** —
zoledronic acid (ZA) and denosumab — among patients with **metastatic prostate
cancer** who have bone metastases and are receiving systemic treatment
(androgen deprivation therapy [ADT], androgen receptor pathway inhibitors
[ARPI], and/or chemotherapy).

The package runs entirely against an OMOP CDM database. It instantiates the
study cohorts, assembles a target population, derives the treatment-combination
cohorts of interest, and characterizes them with
[CohortDiagnostics](https://ohdsi.github.io/CohortDiagnostics/).

## Features

- Generates the base study cohorts with
  [CohortGenerator](https://ohdsi.github.io/CohortGenerator/).
- Builds the study target table by combining metastasis, bone-metastasis, BPA,
  and systemic-treatment cohorts.
- Derives the BPA / no-BPA populations and the ZA/denosumab × ADT/ARPI/chemo
  treatment-combination cohorts.
- Characterizes the derived cohorts with a custom temporal covariate design
  using CohortDiagnostics.

## Requirements

- R (>= 4.3.3)
- Java (for [DatabaseConnector](https://ohdsi.github.io/DatabaseConnector/) /
  the JDBC drivers)
- A database account with:
  - **read** access to the OMOP CDM schema, and
  - **read / write / delete** access to a results (work) schema.

## Installation

1. Install the HADES dependencies listed in `DESCRIPTION` (via
   [`renv`](https://rstudio.github.io/renv/), which this package uses, or your
   preferred method):

   ```r
   install.packages("renv")
   renv::restore()
   ```

2. Install the package itself:

   ```r
   remotes::install_local("path/to/PioneerBPA")
   # or, during development:
   devtools::install(".")
   ```

## How to run

The single file a site edits and runs is [`extras/codeToRun.R`](extras/codeToRun.R).
Copy it, fill in the site-specific connection details, schema names, and cohort
ids, then source it. It calls the package's main entry point, `execute()`.

A minimal example:

```r
library(PioneerBPA)

connectionDetails <- DatabaseConnector::createConnectionDetails(
  dbms         = "...",
  user         = "...",
  password     = "...",
  server       = "...",
  port         = ...,
  pathToDriver = "/path/to/jdbc"
)

PioneerBPA::execute(
  connectionDetails        = connectionDetails,
  cdmDatabaseSchema        = "your_cdm",           # read-only CDM
  vocabularyDatabaseSchema = "your_cdm",           # usually same as CDM
  cohortDatabaseSchema     = "your_results",       # read/write/delete
  cohortTable              = "cohortBPA",
  cohortTableNew           = "cohortTableNew",
  targetTable              = "targetTable",
  outputFolder             = "/path/to/output",
  databaseId               = "YourDb",
  databaseName             = "Your database",
  databaseDescription      = "Your database description",
  targetMetastasis         = 1768,
  targetBones              = 1769,
  bpaZa                    = 1770,
  bpaDenosumab             = 1771,
  adt                      = 1772,
  arpi                     = 1773,
  chemo                    = 1774
)
```

`execute()` runs the study steps, each individually switchable via its
`generateCohorts` / `createTargetTable` / `createDerivedCohorts` /
`runDiagnostics` / `runIRandTTEAnalysis` / `runComparativeEffectiveness`
arguments so a site can re-run just part of the study.

Results are written under `outputFolder`: cohort counts and optional cohort
statistics; a `diagnostics/` folder (CohortDiagnostics); an `IRandTTEAnalysis/`
folder (incidence rates + Kaplan-Meier); and a `comparativeEffectiveness/`
folder (propensity plot, comparability decision, covariate balance, Cox HRs).

## Package structure

Each analytical function lives in its own file under `R/`, with inline
documentation.

| File | Function | Role |
|------|----------|------|
| `R/execute.R` | `execute()` | **Main entry point** — orchestrates the steps below. |
| `R/generateStudyCohorts.R` | `generateStudyCohorts()` | Instantiates the base study cohorts on the CDM. |
| `R/createTargetTable.R` | `createTargetTable()` | Combines metastasis + bone + BPA + systemic-treatment cohorts into the target table. |
| `R/createDerivedCohorts.R` | `createDerivedCohorts()` | Builds the derived treatment-combination cohorts. |
| `R/createCohortTableNew.R` | `createCohortTableNew()` | Creates (drop-and-recreate) the derived cohort table. |
| `R/appendDerivedCohorts.R` | `appendDerivedCohortsToBase()` | Copies the derived target cohorts into the base cohort table (end-of-observation end date) so targets and outcomes share one table. |
| `R/runDerivedCohortDiagnostics.R` | `runDerivedCohortDiagnostics()` | Runs CohortDiagnostics on the derived cohorts. |
| `R/runIRandTTE.R` | `runIRandTTEAnalysis()` | Incidence rates (Poisson CI) and Kaplan-Meier time-to-event for the safety outcomes. |
| `R/runCohortMethodAnalysis.R` | `runCohortMethodAnalysis()` | Comparative effectiveness (denosumab vs ZA): LASSO propensity scores, matching/weighting, Cox models. |
| `R/runTreatmentPatternAnalysis.R` | `runTreatmentPatternAnalysis()` | Dosing-regimen (continuous-exposure) episodes by interval band, and denosumab/ZA switching. |

Supporting resources under `inst/`:

- `inst/cohorts/` — Circe cohort definitions (JSON).
- `inst/sql/sql_server/` — cohort SQL and the derivation scripts.
- `inst/settings/CohortsToCreate.csv` — base cohorts to generate (ids 1768–1774).
- `inst/settings/DerivedCohorts.csv` — derived cohorts (ids 90100–90224); the
  `createDerivedCohorts()` run list is read from this file.

## Cohorts

**Base cohorts** (`inst/settings/CohortsToCreate.csv`):

| id | Cohort |
|----|--------|
| 1768 | Metastatic prostate cancer with a treatment |
| 1769 | Bone metastatic site |
| 1770 | Zoledronic acid (ZA) |
| 1771 | Denosumab |
| 1772 | ADT |
| 1773 | ARPI |
| 1774 | Chemotherapy |

**Derived cohorts** (`inst/settings/DerivedCohorts.csv`): the bone-metastasis
index (90100), the BPA (90200) and no-BPA (90300) populations, the
denosumab (90210) and ZA (90220) first-agent splits, and their ADT / ARPI /
chemotherapy combinations (90211–90214, 90221–90224). See the CSV for the full
descriptions.

## Comparative effectiveness (denosumab vs ZA)

`runCohortMethodAnalysis()` compares the two first-agent arms — denosumab
(`90210`) vs zoledronic acid (`90220`) — with the OHDSI `CohortMethod`
framework: LASSO-regularized propensity scores (`Cyclops`), propensity-score
matching (default) or stabilized IPTW weighting, and Cox proportional-hazards
models over a 3-year risk window for the outcomes in `IRsettings.csv`.

Before any outcome model is fit it writes a **propensity-score plot** and a
**comparability decision** (adequate sample size and overlap); if overlap is
inadequate the outcome models are skipped unless `forceIfNotComparable = TRUE`.
Redundant / highly correlated covariates, and any propensity-model fitting
failure, are logged with the exact `excludedCovariateConceptIds` value to set so
they can be excluded and the analysis re-run.

**Required input:** `excludedCovariateConceptIds` must list the RxNorm
**ingredient** concept ids for denosumab and zoledronic acid (not the cohort ids
1770/1771); their descendants are excluded automatically. Leaving it empty logs
a warning, because the exposure would otherwise leak into the propensity model.

Outputs land in `<outputFolder>/comparativeEffectiveness/`: `ps_90210_vs_90220.png`,
`psModelMetrics.csv`, `comparabilityDecision.csv`, `covariateBalance*.{csv,png}`,
`correlatedCovariates.csv` (if any), and `outcomeModelResults.csv` (hazard
ratios with 95% CIs).

## Treatment patterns (dosing regimens & switching)

`runTreatmentPatternAnalysis()` reconstructs each patient's dosing timeline for
the two arms — denosumab (`90210`) and ZA (`90220`) — from the individual
administration events (cohorts `1771` / `1770`) and splits it into
**continuous-exposure episodes** by dosing-interval band:

- **Denosumab:** every 3–5 weeks, or every 4–7 months.
- **ZA:** every 3–5 weeks, every 11–13 weeks, or every 10–13 months.

An episode is a *maximal run of consecutive administrations whose gaps all fall
in the same band*, so different regimens (e.g. 3–5 wk vs 11–13 wk) are never
merged; a gap outside every band ends the episode. Per arm it reports, for each
band, the number of individuals, the average continuous-treatment length, and
the average number of doses — plus two summary rows: `ALL` (mean index →
last-dose span and dose count over the whole arm) and `NO_REGIMEN` (the same for
patients who match no band). It also detects **switching** to the other agent
more than 30 days after index.

It also reports the **time from the bone-metastasis date to the first BPA
administration** (cohort `90100` → `90200`), overall and by first agent: number
of individuals, mean with a t-based 95% CI, SD, median and interquartile range.
Values can be negative, because the BPA window opens 30 days before the
bone-metastasis date.

Outputs land in `<outputFolder>/treatmentPatterns/`:
`treatmentPatternRegimens.csv`, `treatmentSwitch.csv` and `timeToFirstBpa.csv`.

## Refreshing cohort definitions from Atlas

`inst/settings/insertCohortDefinition.R` uses
[ROhdsiWebApi](https://ohdsi.github.io/ROhdsiWebApi/) to pull cohort definitions
from a WebAPI/Atlas instance into `inst/`. This regenerates the JSON/SQL
resources and is separate from the analysis code above.

## License

`PioneerBPA` is licensed under Apache License 2.0.
