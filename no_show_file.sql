SELECT * FROM medicalappointment
LIMIT 10;

-- change column setting 
ALTER TABLE medicalappointment
	CHANGE COLUMN Hipertension hypertension INT, 
    CHANGE COLUMN Handcap disability_count INT,
    CHANGE COLUMN No_show no_show VARCHAR(3);
    
-- make sure disability ranges from 0-4
SELECT 
	disability_count,
    COUNT(*)
FROM medicalappointment
GROUP BY disability_count;

-- check datatype for date 
SELECT 
	ScheduledDay,
    AppointmentDay
FROM medicalappointment
LIMIT 10;

ALTER TABLE medicalappointment
	MODIFY COLUMN ScheduledDay DATETIME,
    MODIFY COLUMN AppointmentDay DATE;

-- remove the z and t inside date variable
ALTER TABLE medicalappointment
	ADD COLUMN ScheduledDay_clean DATETIME,
    ADD COLUMN AppointmentDay_clean DATE;
    
UPDATE medicalappointment
SET ScheduledDay_clean = STR_TO_DATE(REPLACE(REPLACE(
ScheduledDay, 'T', ''), 'Z', ''), '%Y-%m-%d %H:%i:%s'),
	AppointmentDay_clean = STR_TO_DATE(REPLACE(REPLACE(
AppointmentDay, 'T', ''), 'Z', ''), '%Y-%m-%d');

ALTER TABLE medicalappointment
	DROP COLUMN ScheduledDay,
    DROP COLUMN AppointmentDay;

ALTER TABLE medicalappointment
	CHANGE COLUMN ScheduledDay_clean ScheduledDay DATETIME,
    CHANGE COLUMN AppointmentDay_clean AppointmentDay DATE;

-- check age
SELECT 
	MIN(Age),
	MAX(Age)
FROM medicalappointment;   -- has negative value

DELETE FROM medicalappointment
WHERE Age = -1;

ALTER TABLE medicalappointment ADD COLUMN lead_time_days INT;

UPDATE medicalappointment
SET lead_time_days = DATEDIFF(AppointmentDay, DATE(ScheduledDay));

SELECT 
	MIN(lead_time_days),
    MAX(lead_time_days)
FROM medicalappointment; -- has negative values

SELECT * FROM medicalappointment
WHERE lead_time_days<0;

SET SQL_SAFE_UPDATES = 0;
DELETE FROM medicalappointment
WHERE lead_time_days<0;

-- Data Exploration
-- 1. WHat's overall no-show rate?

SELECT 
	no_show,
    COUNT(*) as total_appointments,
    ROUND(COUNT(*) *100/(SELECT COUNT(*) FROM medicalappointment), 2) as pct_of_total
FROM medicalappointment
GROUP BY no_show; -- 20% no-show

-- 2. Does the day of the week matter
SELECT 
	DAYNAME(AppointmentDay) as appointment_day,
    COUNT(*) as total_appointments,
    SUM(CASE WHEN no_show= 'Yes' THEN 1 ELSE 0 END) as no_shows,
    ROUND(SUM(CASE WHEN no_show= 'Yes' THEN 1 ELSE 0 END)*100/COUNT(*),2) as rate_of_no_shows
FROM medicalappointment
GROUP BY DAYNAME(AppointmentDay)
ORDER BY rate_of_no_shows DESC;

-- 3.Does lead time matter
-- appointment booked on the same day
--  appointment booked on the 1-3 days before
-- appointment booked on the within a week(4-7 days)
-- appointment booked on the long-lead(8+days)
    
SELECT
	CASE
		WHEN lead_time_days = 0 THEN 'Same Day'
        WHEN lead_time_days BETWEEN 1 AND 3 THEN 'Short(1-3 days)'
        WHEN lead_time_days BETWEEN 4 AND 7 THEN 'Within a week'
        ELSE 'Long lead(8+days)'
        END as lead_time_bucket,
	COUNT(*) AS total_appointments,
    ROUND(SUM(CASE WHEN no_show='Yes' THEN 1 ELSE 0 END)*100/COUNT(*),2)AS no_show_rate
    FROM medicalappointment
    GROUP BY lead_time_bucket
    ORDER BY no_show_rate DESC;

-- 4. Age groups(hypothesis: younger patients will miss more appointments)
-- child 0-12
-- teen 13-19
-- young adult 20-39
-- adult 40-59		
SELECT 
	CASE
		WHEN age BETWEEN 0 AND 12 THEN 'child'
        WHEN age BETWEEN 13 AND 19 THEN 'teen'
        WHEN age BETWEEN 20 AND 39 THEN 'yound adult'
        WHEN age BETWEEN 40 AND 59 THEN 'adult'
        ELSE 'senior'
        END as age_group,
	COUNT(*) as total_appointments,
    ROUND(SUM(CASE WHEN no_show = 'Yes' THEN 1 ELSE 0 END)*100/COUNT(*) ,2) as no_show_rate
FROM medicalappointment
GROUP BY age_group
ORDER BY no_show_rate;

-- 5. Do SMS reminders help
SELECT
	CASE
		WHEN sms_received=1 Then 'Received SMS' ELSE 'No SMS'
        END AS sms_status,
	COUNT(*) as total_appointments,
    ROUND(SUM(CASE WHEN no_show = 'Yes' THEN 1 ELSE 0 END)*100/COUNT(*) ,2) as no_show_rate
FROM medicalappointment
GROUP BY sms_status
ORDER BY no_show_rate;
        
-- 6. Which neighborhoods have the highest risk?
SELECT 	
	Neighbourhood,
    COUNT(*) as total_appointments,
	ROUND(SUM(CASE WHEN no_show = 'Yes' THEN 1 ELSE 0 END)*100/COUNT(*) ,2) as no_show_rate,
	RANK() OVER(ORDER BY ROUND(SUM(CASE WHEN no_show='Yes'THEN 1 ELSE 0 END)*100/COUNT(*),2) DESC) as risk_rank
FROM medicalappointment
GROUP BY Neighbourhood
HAVING COUNT(*) >=100
ORDER BY no_show_rate DESC
LIMIT 15; 


-- Patient-level risk scoring 
SELECT
	patientid,
    appointmentid,
    appointmentday,
    no_show,
    COUNT(*) OVER (
		PARTITION BY PatientID
        ORDER BY AppointmentDay
        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING ) AS prior_appointment,
	SUM(CASE WHEN no_show='Yes' THEN 1 ELSE 0 END) OVER
		(partition by PatientID 
        ORDER BY AppointmentDay
        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS prior_no_shows
	FROM medicalappointment
    ORDER BY patentid, appointmentday;
    
    
CREATE VIEW v_appointment_risk AS
WITH patient_history AS(
	SELECT
		PatientId,
        AppointmentID,
        AppointmentDay,
        Neighbourhood,
        lead_time_days,
        sms_received,
        Scholarship,
        no_show,
        COUNT(*) OVER(
			partition by PatientID
            ORDER BY AppointmentDay
            ROWS BETWEEN UNBOUNDED preceding AND 1 preceding
		) AS prior_appointments,
        SUM(CASE WHEN no_show= 'Yes' THEN 1 ELSE 0 END) OVER(
			partition by PatientID
            ORDER BY AppointmentDay
			ROWS BETWEEN UNBOUNDED preceding AND 1 preceding
            ) AS prior_no_shows
		FROM medicalappointment)
	SELECT
		PatientId,
        AppointmentID,
        AppointmentDay,
        Neighbourhood,
        lead_time_days,
        prior_appointments,
        prior_no_shows,
        ROUND(prior_no_shows/NULLIF(prior_appointments,0),2) AS prior_no_show_rate,
        CASE 
			WHEN prior_appointments = 0 THEN 'New Patient- Monitor'
            WHEN (prior_no_shows/ NULLIF(prior_appointments,0)) >=0.5
				 OR lead_time_days>=8 THEN 'High Risk'
			WHEN (prior_no_shows/ NULLIF(prior_appointments,0)) >=0.2
				 OR lead_time_days BETWEEN 4 AND 7  THEN 'Medium Risk'
			ELSE 'Low Risk'
            END AS risk_tier
FROM patient_history;
      
SELECT 
*
FROM v_appointment_risk
WHERE risk_tier ='High Risk'
ORDER BY AppointmentDay
Limit 50;


select * from medicalappointment;
select * from v_appointment_risk; 

    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    

