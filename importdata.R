''
install.packages("DBI")
install.packages("readr")
install.packages("RMariaDB")
library(DBI); library(readr)
library(RMariaDB)
df <- read_csv("C:/Users/fanya/OneDrive - NTNU/Desktop/sqlproject/No_show/medical.csv", col_types = cols(PatientId = col_character()))
names(df) <- gsub("-", "_", names(df))
con <- dbConnect(RMariaDB::MariaDB(), user="root", password="123456",
                 dbname="healthcare_analytic", host="localhost")
dbWriteTable(con, "medicalappointment", df, overwrite = TRUE)
dbGetQuery(con, "SELECT COUNT(*) AS n FROM medicalappointment")
dbGetQuery(con, "SELECT * FROM medicalappointment LIMIT 5")
dbListFields(con, "medicalappointment")