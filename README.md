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

`execute()` runs four steps, each individually switchable via its
`generateCohorts` / `createTargetTable` / `createDerivedCohorts` /
`runDiagnostics` arguments so a site can re-run just part of the study.

Results are written under `outputFolder` (cohort counts, optional cohort
statistics, and a `diagnostics/` folder produced by CohortDiagnostics).

## Package structure

Each analytical function lives in its own file under `R/`, with inline
documentation.

| File | Function | Role |
|------|----------|------|
| `R/execute.R` | `execute()` | **Main entry point** — orchestrates the four steps below. |
| `R/generateStudyCohorts.R` | `generateStudyCohorts()` | Instantiates the base study cohorts on the CDM. |
| `R/createTargetTable.R` | `createTargetTable()` | Combines metastasis + bone + BPA + systemic-treatment cohorts into the target table. |
| `R/createDerivedCohorts.R` | `createDerivedCohorts()` | Builds the derived treatment-combination cohorts. |
| `R/createCohortTableNew.R` | `createCohortTableNew()` | Creates (drop-and-recreate) the derived cohort table. |
| `R/runDerivedCohortDiagnostics.R` | `runDerivedCohortDiagnostics()` | Runs CohortDiagnostics on the derived cohorts. |

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

## Refreshing cohort definitions from Atlas

`inst/settings/insertCohortDefinition.R` uses
[ROhdsiWebApi](https://ohdsi.github.io/ROhdsiWebApi/) to pull cohort definitions
from a WebAPI/Atlas instance into `inst/`. This regenerates the JSON/SQL
resources and is separate from the analysis code above.

## License

`PioneerBPA` is licensed under Apache License 2.0.
