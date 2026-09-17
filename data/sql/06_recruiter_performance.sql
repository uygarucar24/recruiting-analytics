WITH recruiter_applications AS (
    SELECT
        job.recruiter_id,
        app.application_id,
        app.days_to_screen,
        app.days_to_hire,

        COALESCE(
            BOOL_OR(event.stage_name = 'Recruiter Screen'),
            FALSE
        ) AS reached_screening,

        COALESCE(
            BOOL_OR(
                event.stage_name IN ('Interview 1', 'Interview 2')
            ),
            FALSE
        ) AS reached_interview,

        COALESCE(
            BOOL_OR(event.stage_name = 'Hired'),
            FALSE
        ) AS reached_hire

    FROM recruiting.applications AS app

    JOIN recruiting.jobs AS job
        ON app.job_id = job.job_id

    LEFT JOIN recruiting.stage_events AS event
        ON app.application_id = event.application_id

    GROUP BY
        job.recruiter_id,
        app.application_id,
        app.days_to_screen,
        app.days_to_hire
),

recruiter_jobs AS (
    SELECT
        recruiter_id,
        COUNT(*) AS jobs_owned,
        ROUND(AVG(difficulty_score), 2) AS avg_difficulty
    FROM recruiting.jobs
    GROUP BY recruiter_id
),

per_recruiter AS (
    SELECT
        rec.recruiter_id,
        rec.experience_level,

        jobs.jobs_owned,
        jobs.avg_difficulty,

        COUNT(*) AS applications,
        COUNT(*) FILTER (WHERE app.reached_screening) AS screenings,
        COUNT(*) FILTER (WHERE app.reached_interview) AS interviews,
        COUNT(*) FILTER (WHERE app.reached_hire) AS hires,

        PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY app.days_to_screen
        ) AS median_days_to_screen,

        PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY app.days_to_hire
        ) AS median_days_to_hire

    FROM recruiter_applications AS app

    JOIN recruiting.recruiters AS rec
        ON app.recruiter_id = rec.recruiter_id

    JOIN recruiter_jobs AS jobs
        ON app.recruiter_id = jobs.recruiter_id

    GROUP BY
        rec.recruiter_id,
        rec.experience_level,
        jobs.jobs_owned,
        jobs.avg_difficulty
),

model AS (
    SELECT
        regr_slope(median_days_to_hire, avg_difficulty)     AS slope,
        regr_intercept(median_days_to_hire, avg_difficulty) AS intercept,
        corr(median_days_to_hire, avg_difficulty)           AS correlation
    FROM per_recruiter
)

SELECT
    rec.recruiter_id,
    rec.experience_level,
    rec.jobs_owned,
    rec.avg_difficulty,

    rec.applications,
    rec.hires,

    ROUND(
        rec.hires * 100.0 / NULLIF(rec.applications, 0),
        2
    ) AS hire_rate_pct,

    ROUND(rec.median_days_to_screen::numeric, 1) AS median_days_to_screen,
    ROUND(rec.median_days_to_hire::numeric, 1)   AS median_days_to_hire,

    ROUND(
        (model.intercept + model.slope * rec.avg_difficulty)::numeric,
        1
    ) AS expected_days_to_hire,

    ROUND(
        (rec.median_days_to_hire
         - (model.intercept + model.slope * rec.avg_difficulty))::numeric,
        1
    ) AS difference_days,

    ROUND(model.correlation::numeric, 2) AS correlation

FROM per_recruiter AS rec

CROSS JOIN model

ORDER BY difference_days;
