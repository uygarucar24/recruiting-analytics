WITH stage_reached AS (
    SELECT
        app.application_id,

        COALESCE(job.department, 'Unbekannt') AS department,

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
            BOOL_OR(event.stage_name = 'Offer'),
            FALSE
        ) AS reached_offer,

        COALESCE(
            BOOL_OR(event.stage_name = 'Hired'),
            FALSE
        ) AS reached_hire,

        COALESCE(
            app.rejection_reason = 'Position already filled',
            FALSE
        ) AS blocked_by_filled_position

    FROM recruiting.applications AS app

    LEFT JOIN recruiting.jobs AS job
        ON app.job_id = job.job_id

    LEFT JOIN recruiting.stage_events AS event
        ON app.application_id = event.application_id

    GROUP BY
        app.application_id,
        COALESCE(job.department, 'Unbekannt'),
        app.rejection_reason
),

department_funnel AS (
    SELECT
        department,

        COUNT(*) AS applications,

        COUNT(*) FILTER (
            WHERE reached_screening
        ) AS screenings,

        COUNT(*) FILTER (
            WHERE reached_interview
        ) AS interviews,

        COUNT(*) FILTER (
            WHERE reached_interview
              AND blocked_by_filled_position
        ) AS interviews_blocked,

        COUNT(*) FILTER (
            WHERE reached_offer
        ) AS offers,

        COUNT(*) FILTER (
            WHERE reached_hire
        ) AS hires

    FROM stage_reached
    GROUP BY department
)

SELECT
    department,
    applications,
    screenings,
    interviews,
    offers,
    hires,

    ROUND(
        screenings * 100.0 / NULLIF(applications, 0),
        2
    ) AS application_to_screen_pct,

    ROUND(
        interviews * 100.0 / NULLIF(screenings, 0),
        2
    ) AS screen_to_interview_pct,

    ROUND(
        offers * 100.0 / NULLIF(interviews, 0),
        2
    ) AS interview_to_offer_pct,

    interviews_blocked
        AS interviews_blocked_by_filled_position,

    ROUND(
        offers * 100.0
        / NULLIF(interviews - interviews_blocked, 0),
        2
    ) AS interview_to_offer_adjusted_pct,

    ROUND(
        hires * 100.0 / NULLIF(offers, 0),
        2
    ) AS offer_to_hire_pct,

    ROUND(
        hires * 100.0 / NULLIF(applications, 0),
        2
    ) AS overall_hire_rate_pct

FROM department_funnel
ORDER BY
    (department = 'Unbekannt'),
    interview_to_offer_adjusted_pct;
