source("../credentials.r")

JDBC <- "/home/a_kiselev/Jdbc"
connectionDetails <- DatabaseConnector::createConnectionDetails(
  dbms        = DBMS,
  user        = USER,
  password    = PASSWORD,
  server      = SERVER,
  port        = DB_PORT,
  pathToDriver = JDBC
)
connection <- DatabaseConnector::connect(connectionDetails)

DatabaseConnector::querySql(connection,
                            "SELECT cohort_definition_id, COUNT(subject_id)
                            FROM marketscan_ccaemdcr_aug2025_results.cohortBPA
                            GROUP BY cohort_definition_id
                            ORDER BY cohort_definition_id")

DatabaseConnector::querySql(connection,
                            "SELECT bpa_type, count(subject_id)
                            FROM marketscan_ccaemdcr_aug2025_results.targetTable
                            GROUP BY bpa_type")


DatabaseConnector::querySql(connection,
                            "SELECT *
                            FROM marketscan_ccaemdcr_aug2025_results.targetTable
                            WHERE bpa_type = 'AA'")

DatabaseConnector::querySql(connection,
                            "SELECT *
                            FROM #cohort_src
                            LIMIT 10")
