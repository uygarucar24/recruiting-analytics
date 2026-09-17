DROP SCHEMA IF EXISTS bi CASCADE;
CREATE SCHEMA bi;

CREATE VIEW bi.dim_job AS
SELECT
    job_id,
    job_title,
    department,
    location,
    seniority,
    work_model,
    job_status,
    opening_date,
    close_date,
    target_hires,
    difficulty_score,
    salary_min_eur,
    salary_max_eur,

    CASE
        WHEN difficulty_score < 2.5 THEN '1 leicht'
        WHEN difficulty_score < 3.5 THEN '2 mittel'
        WHEN difficulty_score < 4.5 THEN '3 schwer'
        ELSE '4 sehr schwer'
    END AS difficulty_band

FROM recruiting.jobs;

CREATE VIEW bi.dim_recruiter AS
SELECT
    rec.recruiter_id,
    rec.experience_level,
    rec.specialization,
    rec.office,
    rec.start_date,

    jobs.jobs_owned,
    jobs.avg_difficulty

FROM recruiting.recruiters AS rec

LEFT JOIN (
    SELECT
        recruiter_id,
        COUNT(*) AS jobs_owned,
        ROUND(AVG(difficulty_score), 2) AS avg_difficulty
    FROM recruiting.jobs
    GROUP BY recruiter_id
) AS jobs ON rec.recruiter_id = jobs.recruiter_id;

CREATE VIEW bi.dim_source AS
SELECT
    source_id,
    source_name,
    source_category,
    estimated_cost_per_application_eur
FROM recruiting.sources;

CREATE VIEW bi.dim_candidate AS
WITH consent_per_candidate AS (
    SELECT DISTINCT ON (candidate_id)
        candidate_id,
        data_processing_consent AS latest_consent,
        COUNT(*) OVER (PARTITION BY candidate_id) AS applications
    FROM recruiting.applications
    WHERE candidate_id IS NOT NULL
    ORDER BY candidate_id, applied_date DESC NULLS LAST, application_id DESC
)
SELECT
    cand.candidate_id,
    cand.age_group,
    cand.years_experience,
    cand.education_level,
    cand.current_location,
    cand.willing_to_relocate,
    cand.preferred_work_model,

    CASE
        WHEN cand.years_experience < 3  THEN '1 unter 3 Jahre'
        WHEN cand.years_experience < 6  THEN '2 drei bis fünf'
        WHEN cand.years_experience < 11 THEN '3 sechs bis zehn'
        ELSE '4 über zehn'
    END AS experience_band,

    COALESCE(consent.applications, 0) AS applications,
    CASE WHEN consent.latest_consent THEN 1 ELSE 0 END AS is_in_talent_pool

FROM recruiting.candidates AS cand
LEFT JOIN consent_per_candidate AS consent
    ON cand.candidate_id = consent.candidate_id;

CREATE VIEW bi.dim_date AS
WITH range AS (
    SELECT
        DATE_TRUNC('year',
            LEAST(MIN(app.applied_date), MIN(job.opening_date)))::date AS start_date,
        (DATE_TRUNC('year',
            GREATEST(MAX(app.applied_date), MAX(job.close_date)))
         + INTERVAL '1 year' - INTERVAL '1 day')::date AS end_date
    FROM recruiting.applications AS app
    CROSS JOIN recruiting.jobs AS job
),

days AS (
    SELECT generate_series(start_date, end_date, INTERVAL '1 day')::date AS date_key
    FROM range
)

SELECT
    date_key,
    EXTRACT(YEAR    FROM date_key)::int AS year,
    EXTRACT(QUARTER FROM date_key)::int AS quarter,
    EXTRACT(MONTH   FROM date_key)::int AS month,
    TO_CHAR(date_key, 'YYYY-MM')        AS year_month,
    EXTRACT(WEEK    FROM date_key)::int AS calendar_week,
    EXTRACT(DAY     FROM date_key)::int AS day_of_month,
    EXTRACT(ISODOW  FROM date_key)::int AS weekday_number,

    CASE EXTRACT(MONTH FROM date_key)::int
        WHEN  1 THEN 'Januar'    WHEN  2 THEN 'Februar'  WHEN  3 THEN 'März'
        WHEN  4 THEN 'April'     WHEN  5 THEN 'Mai'      WHEN  6 THEN 'Juni'
        WHEN  7 THEN 'Juli'      WHEN  8 THEN 'August'   WHEN  9 THEN 'September'
        WHEN 10 THEN 'Oktober'   WHEN 11 THEN 'November' ELSE 'Dezember'
    END AS month_name,

    CASE EXTRACT(ISODOW FROM date_key)::int
        WHEN 1 THEN 'Montag'     WHEN 2 THEN 'Dienstag'  WHEN 3 THEN 'Mittwoch'
        WHEN 4 THEN 'Donnerstag' WHEN 5 THEN 'Freitag'   WHEN 6 THEN 'Samstag'
        ELSE 'Sonntag'
    END AS weekday_name,

    EXTRACT(ISODOW FROM date_key)::int >= 6 AS is_weekend

FROM days;

CREATE VIEW bi.fact_application AS
WITH stage_reached AS (
    SELECT
        application_id,
        BOOL_OR(stage_name = 'Recruiter Screen')                  AS reached_screening,
        BOOL_OR(stage_name IN ('Interview 1', 'Interview 2'))     AS reached_interview,
        BOOL_OR(stage_name = 'Offer')                             AS reached_offer,
        BOOL_OR(stage_name = 'Hired')                             AS reached_hire
    FROM recruiting.stage_events
    GROUP BY application_id
),

interview_score AS (
    SELECT
        application_id,
        ROUND(AVG(score), 2) AS interview_score_avg
    FROM recruiting.interviews
    WHERE score IS NOT NULL
    GROUP BY application_id
)

SELECT
    app.application_id,

    app.candidate_id,
    app.job_id,
    app.source_id,
    job.recruiter_id,

    app.applied_date,
    app.screen_date,
    app.interview_1_date,
    app.interview_2_date,
    app.offer_date,
    app.hire_date,
    app.offer_declined_date,
    app.rejected_date,
    app.withdrawal_date,

    app.application_status,
    app.last_stage,
    app.rejection_reason,
    app.salary_expectation_eur,
    app.salary_is_plausible,
    app.data_processing_consent AS talent_pool_consent,

    1 AS is_application,
    CASE WHEN COALESCE(stage.reached_screening, FALSE) THEN 1 ELSE 0 END AS is_screened,
    CASE WHEN COALESCE(stage.reached_interview, FALSE) THEN 1 ELSE 0 END AS is_interviewed,
    CASE WHEN COALESCE(stage.reached_offer,     FALSE) THEN 1 ELSE 0 END AS is_offered,
    CASE WHEN COALESCE(stage.reached_hire,      FALSE) THEN 1 ELSE 0 END AS is_hired,

    CASE
        WHEN app.rejection_reason = 'Position already filled' THEN 1 ELSE 0
    END AS is_blocked_by_filled_position,

    app.days_to_screen,
    app.days_screen_to_interview,
    app.days_interview_to_offer,
    app.days_offer_to_response,
    app.days_to_hire,

    offer.planned_start_date,
    (offer.planned_start_date - app.hire_date)    AS days_hire_to_start,
    (offer.planned_start_date - app.applied_date) AS days_to_start,

    score.interview_score_avg,

    src.estimated_cost_per_application_eur AS cost_eur

FROM recruiting.applications AS app

LEFT JOIN recruiting.jobs     AS job   ON app.job_id    = job.job_id
JOIN      recruiting.sources  AS src   ON app.source_id = src.source_id
LEFT JOIN recruiting.offers   AS offer ON app.application_id = offer.application_id
LEFT JOIN stage_reached       AS stage ON app.application_id = stage.application_id
LEFT JOIN interview_score     AS score ON app.application_id = score.application_id;

CREATE VIEW bi.fact_recruiter_performance AS
WITH per_recruiter AS (
    SELECT
        job.recruiter_id,
        COUNT(*) FILTER (WHERE app.hire_date IS NOT NULL) AS hires,
        COUNT(*) AS applications,
        PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY app.days_to_hire
        ) AS median_days_to_hire
    FROM recruiting.applications AS app
    JOIN recruiting.jobs AS job ON app.job_id = job.job_id
    GROUP BY job.recruiter_id
),

recruiter_jobs AS (
    SELECT recruiter_id, ROUND(AVG(difficulty_score), 2) AS avg_difficulty
    FROM recruiting.jobs
    GROUP BY recruiter_id
),

points AS (
    SELECT
        rec.recruiter_id,
        rec.applications,
        rec.hires,
        rec.median_days_to_hire,
        jobs.avg_difficulty
    FROM per_recruiter AS rec
    JOIN recruiter_jobs AS jobs ON rec.recruiter_id = jobs.recruiter_id
),

model AS (
    SELECT
        regr_slope(median_days_to_hire, avg_difficulty)     AS slope,
        regr_intercept(median_days_to_hire, avg_difficulty) AS intercept,
        corr(median_days_to_hire, avg_difficulty)           AS correlation
    FROM points
)

SELECT
    points.recruiter_id,
    points.applications,
    points.hires,
    points.avg_difficulty,
    ROUND(points.median_days_to_hire::numeric, 1) AS median_days_to_hire,
    ROUND(
        (model.intercept + model.slope * points.avg_difficulty)::numeric, 1
    ) AS expected_days_to_hire,
    ROUND(
        (points.median_days_to_hire
         - (model.intercept + model.slope * points.avg_difficulty))::numeric, 1
    ) AS difference_days,
    ROUND(model.correlation::numeric, 2) AS correlation
FROM points
CROSS JOIN model;

CREATE VIEW bi.dim_stage AS
SELECT * FROM (
    VALUES
        (1, 'Bewerbungen'),
        (2, 'Screening'),
        (3, 'Interview'),
        (4, 'Angebot'),
        (5, 'Einstellung')
) AS stage (stage_order, stage_name);

CREATE VIEW bi.dim_step AS
SELECT * FROM (
    VALUES
        (1, 'Bewerbung bis Screening'),
        (2, 'Screening bis Interview'),
        (3, 'Interview bis Angebot'),
        (4, 'Angebot bis Antwort')
) AS step (step_order, step_name);

SELECT 'fact_application  Zeilen' AS pruefung, COUNT(*)::text AS wert
FROM bi.fact_application
UNION ALL SELECT 'davon Screening erreicht', SUM(is_screened)::text    FROM bi.fact_application
UNION ALL SELECT 'davon Interview erreicht', SUM(is_interviewed)::text FROM bi.fact_application
UNION ALL SELECT 'davon Angebot erhalten',   SUM(is_offered)::text     FROM bi.fact_application
UNION ALL SELECT 'davon eingestellt',        SUM(is_hired)::text       FROM bi.fact_application
UNION ALL SELECT 'davon mit Starttermin',    COUNT(planned_start_date)::text
          FROM bi.fact_application
UNION ALL SELECT 'dim_job',       COUNT(*)::text FROM bi.dim_job
UNION ALL SELECT 'dim_candidate', COUNT(*)::text FROM bi.dim_candidate
UNION ALL SELECT 'Personen im Talentpool', SUM(is_in_talent_pool)::text
          FROM bi.dim_candidate
UNION ALL SELECT 'dim_recruiter', COUNT(*)::text FROM bi.dim_recruiter
UNION ALL SELECT 'dim_source',    COUNT(*)::text FROM bi.dim_source
UNION ALL SELECT 'dim_date',      COUNT(*)::text FROM bi.dim_date
UNION ALL SELECT 'dim_stage',     COUNT(*)::text FROM bi.dim_stage
UNION ALL SELECT 'dim_step',      COUNT(*)::text FROM bi.dim_step
UNION ALL SELECT 'fact_recruiter_performance', COUNT(*)::text
          FROM bi.fact_recruiter_performance
UNION ALL
SELECT 'Kalender ohne Lücken',
       CASE WHEN COUNT(*) = 0 THEN 'ja' ELSE 'NEIN' END
FROM (
    SELECT date_key - LAG(date_key) OVER (ORDER BY date_key) AS abstand
    FROM bi.dim_date
) AS gaps
WHERE abstand <> 1;
