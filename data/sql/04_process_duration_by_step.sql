WITH steps AS (
    SELECT
        COALESCE(job.department, 'Unbekannt') AS department,
        step.step_order,
        step.step_name,
        step.days

    FROM recruiting.applications AS app

    LEFT JOIN recruiting.jobs AS job
        ON app.job_id = job.job_id

    LEFT JOIN recruiting.offers AS offer
        ON app.application_id = offer.application_id

    CROSS JOIN LATERAL (
        VALUES
            (1, 'Bewerbung bis Screening',      app.days_to_screen),
            (2, 'Screening bis Interview 1',    app.days_screen_to_interview),
            (3, 'Interview bis Angebot',        app.days_interview_to_offer),
            (4, 'Angebot bis Antwort',          app.days_offer_to_response),
            (5, 'Gesamt: Bewerbung bis Zusage', app.days_to_hire),
            (6, 'Zusage bis geplantem Arbeitsbeginn',
                (offer.planned_start_date - app.hire_date)),
            (7, 'Gesamt: Bewerbung bis geplantem Arbeitsbeginn',
                (offer.planned_start_date - app.applied_date))
    ) AS step(step_order, step_name, days)

    WHERE step.days IS NOT NULL
)

SELECT
    step.step_order,
    step.step_name,

    COALESCE(step.department, 'Gesamt') AS department,

    COUNT(*) AS n,

    PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY step.days
    ) AS median_days,

    PERCENTILE_CONT(0.9) WITHIN GROUP (
        ORDER BY step.days
    ) AS p90_days,

    MAX(step.days) AS max_days

FROM steps AS step

GROUP BY GROUPING SETS (
    (step.step_order, step.step_name),
    (step.step_order, step.step_name, step.department)
)

ORDER BY
    step.step_order,
    (step.department IS NOT NULL),
    median_days DESC;
