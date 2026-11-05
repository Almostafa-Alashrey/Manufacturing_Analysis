/*
                            Manufacturing Data Warehouse - SQL Project Overview

1. Data Exploration & Quality Checks
        Purpose: Understand the dataset,and verify data ranges.

2. Machine Utilization & Downtime and Failure Analysis
        Purpose: Deep-dive into machine performance, identify problem areas, and analyze root causes of failures.

3. OEE-Style Analysis (Overall Equipment Effectiveness)
        Purpose: Measure manufacturing efficiency using OEE.

4.Time Trend Analysis
        Purpose: Track performance metrics over time to spot patterns or recurring issues.

5.ENERGY,Production & Healthy Analysis 
        Purpose: Assess how machine health and energy usage impact overall production output.

6. Database Views:
       -vw_machine_performance
       -vw_factory_overview
 
7. Stored Procedures
       -usp_ManufacturingProcedures (@StartDate, @EndDate)

8. Key Performance Indicators (KPIs):
       -total_monitoring_records
       -total_active_machines
       -total_factors
       -total_machines_models
       -total_manufacturers
       -total_production_lines
       -total_downtime_hours
       -total_idle_hours
       -total_energy_consumption_kwh
       -avg_health_score
       -energy_per_operational_hour_kwh
*/

----------------------------------------------
-- 01. DATA EXPLORATION & QUALITY CHECKS
----------------------------------------------
USE ManufacturingDW;
GO
--Q01. How Many Rows in each table?

SELECT 'machines' AS table_name, COUNT(*) AS row_count FROM dim_machine
UNION ALL SELECT 'factories', COUNT(*) FROM dim_factory
UNION ALL SELECT 'failure types', COUNT(*) FROM dim_failure_type
UNION ALL SELECT 'maintenance types', COUNT(*) FROM dim_maintenance_type
UNION ALL SELECT 'production lines', COUNT(*) FROM dim_production_line
UNION ALL SELECT 'shifts', COUNT(*) FROM dim_shift
UNION ALL SELECT 'days number', COUNT(*) FROM dim_date;

--Q02. How many readings does each machine have?
WITH machines_reading AS (
SELECT machine_key
      ,COUNT(monitoring_id) reading_count
FROM fact_maintenance
GROUP BY machine_key
)
SELECT  COUNT(machine_key) machines
       ,MAX(reading_count) max_readings 
       ,MIN(reading_count) min_readings
       ,AVG(reading_count) avg_readings
FROM machines_reading ;

--Q03. Readin Range
SELECT  MIN(d.full_date) first_record
       ,MAX(d.full_date) last_record
       ,COUNT(DISTINCT d.date_key) days_number
       ,CAST(MIN(f.timestamp) AS TIME(0)) first_reading
       ,CAST(MAX(f.timestamp) AS TIME(0)) last_reading
FROM fact_maintenance f
JOIN dim_date d
     ON f.date_key = d.date_key

--Q03. Which factories have the biggest failure and downtime problem?
SELECT  fa.Factory_id
       ,COUNT(DISTINCT f.machine_key) machines_num
       ,ROUND(AVG( m.machine_age * 1.0), 1) AS avg_machine_age
       ,COUNT(DISTINCT m.machine_type) AS machine_types
FROM fact_maintenance f
JOIN dim_factory fa
     ON f.factory_key = fa.factory_key
JOIN dim_machine m
     ON f.machine_key = m.machine_key
GROUP BY fa.Factory_id
ORDER BY machines_num DESC;

--Q04. Which factories have the highest average machine age and variety?
SELECT  fa.Factory_id
       ,ROUND(AVG(m.machine_age * 1.0), 1) AS avg_machine_age
       ,COUNT(DISTINCT m.machine_type) AS machine_types_count
       ,COUNT(DISTINCT f.machine_key) AS total_machines
FROM fact_maintenance f
JOIN dim_factory fa
     ON f.factory_key = fa.factory_key
JOIN dim_machine m
     ON f.machine_key = m.machine_key
GROUP BY fa.Factory_id
ORDER BY total_machines DESC;

------------------------------------------------------------
-- 02. Machine utilization & downtime Failure  analysis
------------------------------------------------------------

--Q05. What is the total downtime across all machines?
SELECT COUNT(machine_key)  downtime_events
      ,SUM(downtime_hours) total_downtime_hours
      ,AVG(downtime_hours) avg_downtime_per_event
      ,MIN(downtime_hours) shortest_downtime_Hour
      ,MAX(downtime_hours) longest_downtime_Hour
FROM fact_maintenance
WHERE downtime_hours > 0;

--Q06. Which machines have the most downtime?
SELECT TOP 10 
        m.machine_id
       ,m.machine_type
       ,m.model
       ,m.machine_age
       ,f.remaining_useful_life_hours 
       ,COUNT(f.machine_key)  downtime_events
       ,SUM(f.downtime_hours) downtime_hours
       ,AVG(f.downtime_hours) AS avg_event_hours
       ,MAX(f.downtime_hours) AS max_event_hours
FROM fact_maintenance f
JOIN dim_machine m
     ON f.machine_key = m.machine_key
GROUP BY m.machine_id ,m.machine_type,m.machine_age ,m.model,remaining_useful_life_hours
ORDER BY downtime_hours DESC;

--Q07. Who the top 5 manufacturers with the most frequent downtime?
SELECT TOP 5 
        m.manufacturer
       ,COUNT(DISTINCT m.machine_key) machines
       ,COUNT(f.machine_key)  downtime_events
       ,SUM(f.machine_failure) failures
       ,SUM(f.downtime_hours) downtime_hours
       ,AVG(f.downtime_hours)  avg_event_hours
       ,MAX(f.downtime_hours)  max_event_hours
FROM fact_maintenance f
JOIN dim_machine m
     ON f.machine_key = m.machine_key
GROUP BY m.manufacturer
ORDER BY downtime_hours DESC;

--Q08. Which 10 machine Models fail the most?
WITH failed_models AS (
    SELECT m.model
           ,COUNT(DISTINCT m.machine_key) machines
           ,COUNT(monitoring_id) readings
           ,SUM(f.machine_failure) failures
    FROM fact_maintenance f
    JOIN dim_machine m 
         ON m.machine_key = f.machine_key
    GROUP BY m.model
)
SELECT TOP (10) 
       model
       ,machines
       ,readings
       ,failures
FROM failed_models
ORDER BY failures DESC;

--Q09. What are the main causes of downtime?
WITH downtime_summary AS
(
    SELECT ft.failure_type downtime_reason
        ,SUM(f.downtime_hours) downtime_hours
    FROM fact_maintenance f
    INNER JOIN dim_failure_type ft
        ON f.failure_type_key = ft.failure_type_key
    WHERE f.machine_failure = 1
    GROUP BY ft.failure_type
),
downtime_ranked AS
(
    SELECT
        downtime_reason
        ,downtime_hours
        ,SUM(downtime_hours) OVER
        (
            ORDER BY downtime_hours DESC
            ROWS BETWEEN UNBOUNDED PRECEDING
            AND CURRENT ROW
        ) AS cumulative_downtime,
        SUM(downtime_hours) OVER ()
        AS total_downtime
    FROM downtime_summary
)
SELECT
    downtime_reason
    ,downtime_hours downtime_hours
    ,CAST(
        100.0 * downtime_hours
        / NULLIF(total_downtime, 0)
        AS DECIMAL(10,2)
    ) AS contribution_pct
    ,CAST(
        100.0 * cumulative_downtime
        / NULLIF(total_downtime, 0)
        AS DECIMAL(10,2)
    ) AS cumulative_contribution_pct
FROM downtime_ranked
ORDER BY downtime_hours DESC;

--Q10. What is the monthly downtime trend?
SELECT  CONCAT(d.year,'-',d.month )  month
       ,SUM(f.downtime_hours) downtime_hours
       ,SUM(f.machine_failure) failures_num
FROM fact_maintenance f
JOIN dim_date d
    ON  f.date_key=d.date_key
JOIN dim_failure_type ft
    ON  f.failure_type_key=ft.failure_type_key
WHERE f.downtime_hours > 0
GROUP BY CONCAT(d.year,'-',d.month ) 
ORDER BY month

--Q11. Which shifts record the highest downtime hours?
SELECT  s.factory_shift
       ,COUNT(f.machine_key) AS downtime_events
       ,SUM(f.downtime_hours) downtime_hours
       ,AVG(f.downtime_hours) avg_downtime_hours
FROM fact_maintenance f
JOIN dim_date d
    ON  f.date_key=d.date_key
JOIN dim_shift s
    ON  f.shift_key = s.shift_key
WHERE f.downtime_hours > 0
GROUP BY s.factory_shift
ORDER BY downtime_hours DESC

--Q12. Which failure type caused the most downtime each week?
WITH weekly_failure_counts AS (
    SELECT 
         d.year year
        ,d.week_of_year
        ,ft.failure_type
        ,COUNT(f.machine_key) failure_count
        ,SUM(f.downtime_hours)  total_downtime_hours
        ,ROW_NUMBER() OVER (
            PARTITION BY d.year, d.week_of_year 
            ORDER BY COUNT(f.machine_key) DESC, SUM(f.downtime_hours) DESC
        ) rnk
    FROM fact_maintenance f
    JOIN dim_date d
        ON f.date_key = d.date_key
    JOIN dim_failure_type ft
        ON f.failure_type_key = ft.failure_type_key
    WHERE ft.failure_type <> 'No Failure'
    GROUP BY d.year, d.week_of_year, ft.failure_type
)
SELECT 
     year
    ,week_of_year
    ,failure_type  most_frequent_failure
    ,failure_count
    ,total_downtime_hours
FROM weekly_failure_counts
WHERE rnk = 1
ORDER BY year ASC, week_of_year ASC;

--Q13. Which factories have the biggest downtime problem?
SELECT  TOP 5 
        fa.Factory_id
       ,COUNT(DISTINCT m.machine_id) machines_count
       ,SUM(f.downtime_hours) total_downtime_hours
       ,AVG(f.downtime_hours) avg_downtime_hours
FROM fact_maintenance f
JOIN dim_factory fa
     ON f.factory_key = fa.factory_key
JOIN dim_machine m
     ON f.machine_key = m.machine_key
WHERE f.downtime_hours >0
GROUP BY fa.Factory_id
ORDER BY total_downtime_hours DESC;

--Q14. What does each failure type cost
SELECT ft.failure_type
       ,COUNT(*) failures
       ,SUM(f.maintenance_cost) maintenance_cost
       ,AVG(f.maintenance_cost) avg_cost_per_failure
       ,ROUND(SUM(f.downtime_hours) / 60.0, 0) downtime_hours
FROM fact_maintenance f
JOIN dim_failure_type ft ON ft.failure_type_key = f.failure_type_key
WHERE f.machine_failure = 1
GROUP BY ft.failure_type
ORDER BY maintenance_cost DESC;

--Q15. What is the breakdown of downtime and maintenance cost by machine age?
WITH age_seg AS (
    SELECT CASE WHEN dm.machine_age <= 5  THEN '3-5 years'
                WHEN dm.machine_age <= 8  THEN '6-8 years'
                WHEN dm.machine_age <= 11 THEN '9-11 years'
                ELSE '12+ years' END AS age_segments
           ,dm.machine_key
           ,f.downtime_hours
           ,f.maintenance_cost
    FROM fact_maintenance f
    JOIN dim_machine dm ON dm.machine_key = f.machine_key
)
SELECT  age_segments
       ,COUNT(DISTINCT machine_key) AS machines
       ,COUNT(*) AS readings
       ,SUM(downtime_hours) total_downtime_hours
       ,AVG(downtime_hours) avg_downtime_hours
       ,AVG(maintenance_cost)avg_maintenance_cost
FROM age_seg
GROUP BY age_segments
ORDER BY total_downtime_hours ;

--Q16. What kinds of failures hit younger machines?
WITH machine_age_class AS (
    SELECT CASE WHEN m.machine_age <= 7 THEN 'Younger (<=7 yrs)' ELSE 'Older (7+ yrs)' END AS age_group,
           ft.failure_type
    FROM fact_maintenance f
    JOIN dim_machine m 
        ON m.machine_key = f.machine_key
    JOIN dim_failure_type ft 
        ON ft.failure_type_key = f.failure_type_key
    WHERE f.machine_failure = 1
)
SELECT age_group, failure_type, COUNT(*)  failures,
      100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY age_group)  pct_within_age_group
FROM machine_age_class
WHERE age_group='Younger (<=7 yrs)'
GROUP BY age_group, failure_type
ORDER BY age_group, failures DESC;

--Q17. What kinds of failures hit older machines?
WITH machine_age_class AS (
    SELECT CASE WHEN dm.machine_age <= 7 THEN 'Younger (<=7 yrs)' ELSE 'Older (7+ yrs)' END AS age_group,
           ft.failure_type
    FROM fact_maintenance f
    JOIN dim_machine      dm ON dm.machine_key      = f.machine_key
    JOIN dim_failure_type ft ON ft.failure_type_key = f.failure_type_key
    WHERE f.machine_failure = 1
)
SELECT age_group, failure_type, COUNT(*)  failures,
      100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY age_group)  pct_within_age_group
FROM machine_age_class
WHERE age_group='Older (7+ yrs)'
GROUP BY age_group, failure_type
ORDER BY age_group, failures DESC;

-- Q18. What is the distribution and count of machines across different failure frequency segments?
WITH failure_segmentaion AS (
    SELECT machine_key
    ,SUM(machine_failure) failures
    ,SUM(downtime_hours) downtime_hours
    FROM fact_maintenance
    GROUP BY machine_key
),
c AS (
    SELECT CASE WHEN failures = 0 THEN 'Never failed'
                WHEN failures = 1 THEN 'Failed once'
                ELSE 'Repeat offender +2' END AS failure_segment,
           machine_key, failures, downtime_hours
    FROM failure_segmentaion
)
SELECT failure_segment,
       COUNT(*) machines,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) pct_of_machines,
       SUM(failures) failures,
       ROUND(100.0 * SUM(downtime_hours) / SUM(SUM(downtime_hours)) OVER (), 1)pct_of_downtime
FROM c
GROUP BY failure_segment
ORDER BY failures ASC;

-- Q19. Do heavily-used machines fail more?
WITH usage_q AS (
    SELECT machine_failure
          ,operating_hours
          ,downtime_hours
          ,NTILE(4) OVER (ORDER BY operating_hours DESC) usage_quartile
    FROM fact_maintenance
)
SELECT usage_quartile
       ,ROUND(MIN(operating_hours), 0) min_operating_hours
       ,ROUND(MAX(operating_hours), 0)  max_operating_hours
       ,COUNT(*) readings_num
       ,ROUND(100.0 * SUM(machine_failure) / COUNT(*), 2) AS failure_rate_pct
       ,ROUND(AVG(downtime_hours), 1) avg_downtime_hours
FROM usage_q
GROUP BY usage_quartile
ORDER BY usage_quartile;

-- Q20. What is Worst 3 machines inside each factory?
WITH base_table AS (
    SELECT fa.factory_id factory_id
           ,m.machine_id machine_id
           ,m.machine_type machine_type
           ,SUM(f.machine_failure) failures
           ,SUM(f.downtime_hours) downtime_hours
    FROM fact_maintenance f
    JOIN dim_machine m 
         ON m.machine_key = f.machine_key
    JOIN dim_factory fa 
         ON fa.factory_key = f.factory_key
    GROUP BY fa.factory_id, f.machine_key,m.machine_id, m.machine_type
),
ranking AS (
    SELECT  factory_id
           ,machine_id
           ,machine_type
           ,failures
           ,downtime_hours
           ,ROW_NUMBER() OVER (PARTITION BY factory_id ORDER BY failures DESC, downtime_hours DESC, machine_id) AS rnk
    FROM base_table
)
SELECT factory_id
       ,rnk  factory_rnk
       ,machine_id
       ,machine_type
       ,failures
       ,ROUND(downtime_hours, 1) AS downtime_hours
FROM ranking
WHERE rnk <= 3
ORDER BY factory_id, rnk;

------------------------------------------------------------
-- 03.  OEE-STYLE ANALYSIS
------------------------------------------------------------

-- Q21.What is the overall OEE score across each factory?
SELECT 
     fa.factory_id
    ,ROUND(100.0 * (1.0 - SUM(m.downtime_hours) / NULLIF(SUM(m.shift_hours), 0)), 2) AS availability_pct
    ,ROUND(AVG(m.production_rate), 2) AS performance_pct
    ,ROUND(
        (100.0 * (1.0 - SUM(m.downtime_hours) / NULLIF(SUM(m.shift_hours), 0))) 
        * AVG(m.production_rate) / 100.0
     , 2) AS oee_lite_pct
FROM fact_maintenance m
JOIN dim_factory fa 
    ON fa.factory_key = m.factory_key
GROUP BY fa.factory_id
ORDER BY oee_lite_pct ASC;

-- Q22. Which machine types achieve the highest and lowest OEE scores?
SELECT 
     m.machine_type
    ,COUNT(DISTINCT m.machine_key) machine_count
    ,ROUND(100.0 * (1.0 - SUM(f.downtime_hours) / NULLIF(SUM(f.shift_hours), 0)), 2)  availability_pct
    ,ROUND(AVG(f.production_rate), 2)  performance_pct
    ,ROUND(
        (100.0 * (1.0 - SUM(f.downtime_hours) / NULLIF(SUM(f.shift_hours), 0))) 
        * AVG(f.production_rate) / 100.0
     , 2) AS oee_lite_pct
FROM fact_maintenance f
JOIN dim_machine m 
     ON m.machine_key = f.machine_key
GROUP BY m.machine_type
ORDER BY oee_lite_pct DESC;

-- Q23. Which individual machines are the worst performers in terms of Availability?
SELECT TOP 10
     m.machine_id
    ,m.machine_type
    ,m.manufacturer
    ,SUM(f.downtime_hours) AS total_downtime_hours
    ,SUM(f.shift_hours) AS total_shift_hours
    ,ROUND(100.0 * (1.0 - SUM(f.downtime_hours) / NULLIF(SUM(m.shift_hours), 0)), 2) AS availability_pct
FROM fact_maintenance f
JOIN dim_machine m 
     ON m.machine_key = f.machine_key
GROUP BY m.machine_id, m.machine_type, m.manufacturer
ORDER BY availability_pct ASC;

-- Q23. How does OEE vary across different factory shifts ?
SELECT 
     s.factory_shift
    ,ROUND(100.0 * (1.0 - SUM(f.downtime_hours) / NULLIF(SUM(f.shift_hours), 0)), 2) AS availability_pct
    ,ROUND(AVG(f.production_rate), 2) AS performance_pct
    ,ROUND(
        (100.0 * (1.0 - SUM(f.downtime_hours) / NULLIF(SUM(f.shift_hours), 0))) 
        * AVG(f.production_rate) / 100.0
     , 2) AS oee_lite_pct
FROM fact_maintenance f
JOIN dim_shift s 
     ON s.shift_key = f.shift_key
GROUP BY s.factory_shift
ORDER BY oee_lite_pct DESC;

------------------------------------------------------------
-- 04.   TIME TREND ANALYSIS
------------------------------------------------------------

-- Q24. Daily trend: failures, failure rate and downtime
SELECT d.full_date,
       COUNT(*) readings,
       SUM(f.machine_failure)  failures,
       ROUND(100.0 * SUM(f.machine_failure) / COUNT(*), 2) failure_rate_pct,
       SUM(f.downtime_hours) downtime_hours,
       ROUND(AVG(f.energy_consumption_kwh), 1) avg_energy_kwh
FROM fact_maintenance f
JOIN dim_date d 
     ON d.date_key = f.date_key
GROUP BY d.full_date
ORDER BY d.full_date;

-- Q25. Weekly trend : failures, failure rate and downtime
SELECT d.week_of_year,
       MIN(d.full_date) week_start,
       COUNT(DISTINCT d.date_key) days_in_week,
       COUNT(*) readings,
       SUM(f.machine_failure) failures,
       ROUND(100.0 * SUM(f.machine_failure) / COUNT(*), 2) failure_rate_pct,
       SUM(f.downtime_hours) downtime_hours,
       ROUND(SUM(f.maintenance_cost), 0) maintenance_cost
FROM fact_maintenance f
JOIN dim_date d ON d.date_key = f.date_key
GROUP BY d.week_of_year
ORDER BY d.week_of_year;

-- Q26. Month-over-month change (MOM)
WITH m AS (
    SELECT d.year AS year
           ,d.month AS month
           ,d.month_name
           ,COUNT(DISTINCT d.date_key) days_number
           ,SUM(f.machine_failure) failures
           ,100.0 * SUM(f.machine_failure) / COUNT(*) failure_rate_pct
           ,SUM(f.downtime_hours) / COUNT(DISTINCT d.date_key) downtime_hours_per_day
    FROM fact_maintenance f
    JOIN dim_date d 
         ON d.date_key = f.date_key
    GROUP BY d.year, d.month, d.month_name
)
SELECT  year
       ,month
       ,month_name
       ,days_number
       ,ROUND(failure_rate_pct, 2) failure_rate_pct
       ,ROUND(LAG(failure_rate_pct) OVER (ORDER BY year, month), 2)  prev_month_failure_rate_pct
       ,ROUND(100.0 * (failure_rate_pct - LAG(failure_rate_pct) OVER (ORDER BY year, month))
             / NULLIF(LAG(failure_rate_pct) OVER (ORDER BY year, month), 0), 1) failure_rate_change_pct
       ,ROUND(downtime_hours_per_day, 1) downtime_hours_per_day
FROM m
ORDER BY year, month;

------------------------------------------------------------
--05. ENERGY ,Production & Healthy Analysis
------------------------------------------------------------

-- Q27. Which machines consume the most energy?
SELECT TOP 10
        m.machine_id
       ,m.model
       ,m.machine_age
       ,SUM(f.energy_consumption_kwh) energy_consumption_kwh
FROM fact_maintenance f
JOIN dim_machine m
     ON f.machine_key =m.machine_key
GROUP BY m.machine_id
        ,m.model
        ,m.machine_age
ORDER BY energy_consumption_kwh DESC

-- Q28. Machine count distribution across production performance & Healthy segments
WITH machine_status AS (
    SELECT 
        m.machine_key
        ,CASE 
            WHEN AVG(f.machine_health_score) >= 80 THEN 'Healthy (>=80)'
            WHEN AVG(f.machine_health_score) >= 60 THEN 'Moderate (60-79)'
            ELSE 'Critical (<60)'
        END AS health_segment
        ,CASE 
            WHEN AVG(f.production_rate) >= 70 THEN 'High Prod'
            WHEN AVG(f.production_rate) >= 50 THEN 'Med Prod'
            ELSE 'Low Prod'
        END AS production_segment
        ,SUM(f.downtime_hours) AS downtime_hours
        ,AVG(f.maintenance_cost) AS maintenance_cost
    FROM fact_maintenance f
    JOIN dim_machine m 
         ON m.machine_key = f.machine_key
    GROUP BY m.machine_key
)
SELECT 
    health_segment,
    production_segment,
    COUNT(DISTINCT machine_key) AS machine_count,
    SUM(downtime_hours) AS total_downtime,
    ROUND(AVG(maintenance_cost), 2) AS avg_maint_cost
FROM machine_status
GROUP BY health_segment, production_segment
ORDER BY health_segment, production_segment;

--Q29. What the highest machines healthy?
SELECT TOP 10
     dm.machine_id
    ,dm.machine_type
    ,ROUND(AVG(f.machine_health_score), 2) AS avg_health_score
    ,SUM(f.downtime_hours) AS total_downtime_hours
    ,ROUND(AVG(f.maintenance_cost), 2) AS avg_maintenance_cost
    ,SUM(f.production_cycles) AS total_production
FROM fact_maintenance f
JOIN dim_machine dm ON dm.machine_key = f.machine_key
GROUP BY dm.machine_id, dm.machine_type
ORDER BY avg_health_score DESC;
 
--Q30. What the least machines healthy?
SELECT TOP 10
     m.machine_id
    ,m.machine_type
    ,ROUND(AVG(f.machine_health_score), 2)  avg_health_score
    ,SUM(f.downtime_hours) total_downtime_hours
    ,ROUND(AVG(f.maintenance_cost), 2) avg_maintenance_cost
    ,SUM(f.production_cycles) total_production
FROM fact_maintenance f
JOIN dim_machine m 
     ON m.machine_key = f.machine_key
GROUP BY m.machine_id, m.machine_type
ORDER BY avg_health_score ASC;


------------------------------------------------------------
-- 06.  Views
------------------------------------------------------------
-- 1. Machine Performance & Health View

CREATE VIEW dbo.vw_machine_performance
AS
SELECT
     m.machine_id
    ,p.production_line
    ,m.machine_type
    ,m.manufacturer
    ,m.model
    ,COUNT(f.monitoring_id) AS total_readings
    ,SUM(f.downtime_hours) AS total_downtime_hours
    ,SUM(f.idle_hours) AS total_idle_hours
    ,SUM(f.energy_consumption_kwh) AS total_energy_kwh
    ,CAST(AVG(f.machine_health_score) AS DECIMAL(5,2)) AS avg_health_score
    ,CAST(AVG(f.remaining_useful_life_hours) AS DECIMAL(10,2)) AS avg_remaining_life_hours
FROM dim_machine m
JOIN fact_maintenance f 
    ON m.machine_key = f.machine_key
JOIN dbo.dim_production_line p 
    ON p.production_line_key = f.production_line_key
GROUP BY 
      m.machine_id
     ,p.production_line, 
     m.machine_type, m.manufacturer, m.model ;

--02. Factory View
CREATE OR ALTER VIEW dbo.vw_factory_overview
AS
SELECT
     fa.factory_id
    ,COUNT(DISTINCT f.machine_key) AS machines_count
    ,SUM(f.downtime_hours) AS total_downtime_hours
    ,SUM(f.energy_consumption_kwh) AS total_energy_kwh
    ,CAST(AVG(f.machine_health_score) AS DECIMAL(5,2)) AS avg_factory_health_score
FROM dbo.dim_factory fa
JOIN dbo.fact_maintenance f 
     ON fa.factory_key = f.factory_key
GROUP BY fa.factory_id;
GO


------------------------------------------------------------
-- 07. STORED PROCEDURE
------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_ManufacturingProcedures
    @StartDate DATE,
    @EndDate DATE
AS
BEGIN

-- 1. Executive Summary
SELECT
    COUNT(f.monitoring_id) AS total_monitoring_records
    ,SUM(f.downtime_hours) AS total_downtime_hours
    ,SUM(f.idle_hours) AS total_idle_hours
    ,SUM(f.energy_consumption_kwh) AS total_energy_kwh
    ,CAST(AVG(f.machine_health_score) AS DECIMAL(5,2)) AS avg_fleet_health_score
FROM fact_maintenance f
JOIN dim_date d 
        ON f.date_key = d.date_key
WHERE d.full_date BETWEEN @StartDate AND @EndDate;

-- 2. Machine Scorecard
SELECT
     m.machine_id
    ,m.machine_type
    ,m.manufacturer
    ,SUM(f.downtime_hours) AS total_downtime_hours
    ,CAST(AVG(f.machine_health_score) AS DECIMAL(5,2)) AS avg_health_score
FROM fact_maintenance f
JOIN dim_machine m 
     ON f.machine_key = m.machine_key
JOIN dbo.dim_date d 
     ON f.date_key = d.date_key
WHERE d.full_date BETWEEN @StartDate AND @EndDate
GROUP BY m.machine_id, m.machine_type, m.manufacturer
ORDER BY total_downtime_hours DESC;

-- 3. Failure Breakdown Scorecard
SELECT
    ft.failure_type
    ,COUNT(f.monitoring_id) AS failure_events
    ,SUM(f.downtime_hours) AS total_downtime_hours
FROM fact_maintenance f
JOIN dbo.dim_failure_type ft 
     ON f.failure_type_key = ft.failure_type_key
JOIN dbo.dim_date d 
     ON f.date_key = d.date_key
WHERE d.full_date BETWEEN @StartDate AND @EndDate
    AND f.machine_failure = 1
GROUP BY ft.failure_type
ORDER BY total_downtime_hours DESC;

-- 4. Shift Performance
SELECT
    s.factory_shift
    ,COUNT(f.monitoring_id) AS shift_readings
    ,SUM(f.downtime_hours) AS total_downtime_hours
    ,CAST(AVG(f.machine_health_score) AS DECIMAL(5,2)) AS avg_shift_health
FROM fact_maintenance f
JOIN dim_shift s 
     ON f.shift_key = s.shift_key
JOIN dim_date d 
     ON f.date_key = d.date_key
WHERE d.full_date BETWEEN @StartDate AND @EndDate
GROUP BY s.factory_shift
ORDER BY total_downtime_hours DESC;
END;


------------------------------------------------------------
-- 8. EXECUTIVE KPIs QUERY
------------------------------------------------------------
SELECT
     COUNT(f.monitoring_id) AS total_monitoring_records
    ,COUNT(DISTINCT f.machine_key) AS total_active_machines
    ,COUNT(DISTINCT f.factory_key) AS total_factors
    ,COUNT(DISTINCT m.model) AS total_machines_models
    ,COUNT(DISTINCT m.manufacturer) total_manufacturers
    ,COUNT(DISTINCT f.production_line_key) total_production_lines
    ,SUM(f.downtime_hours) total_downtime_hours
    ,SUM(f.idle_hours) total_idle_hours
    ,SUM(f.energy_consumption_kwh)  total_energy_consumption_kwh
    ,CAST(AVG(f.machine_health_score) AS DECIMAL(5,2)) avg_health_score
    ,CAST(SUM(f.energy_consumption_kwh) / NULLIF(SUM(f.downtime_hours + f.idle_hours), 0) AS DECIMAL(10,2)) energy_per_operational_hour_kwh
FROM fact_maintenance f
JOIN dim_machine m
    ON f.machine_key =m.machine_key ;















