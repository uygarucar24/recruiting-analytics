WITH stage_reached AS (
    SELECT
        app.application_id,
        src.source_name,
        src.source_category,
        src.estimated_cost_per_application_eur AS cost_per_application,
        app.data_processing_consent,

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
        ) AS reached_hire

    FROM recruiting.applications AS app

    JOIN recruiting.sources AS src
        ON app.source_id = src.source_id

    LEFT JOIN recruiting.stage_events AS event
        ON app.application_id = event.application_id

    GROUP BY
        app.application_id,
        src.source_name,
        src.source_category,
        src.estimated_cost_per_application_eur,
        app.data_processing_consent
),

per_source AS (
    SELECT
        source_name,
        source_category,
        cost_per_application,

        COUNT(*) AS applications,

        COUNT(*) FILTER (WHERE reached_screening) AS screenings,
        COUNT(*) FILTER (WHERE reached_interview) AS interviews,
        COUNT(*) FILTER (WHERE reached_offer)     AS offers,
        COUNT(*) FILTER (WHERE reached_hire)      AS hires,

        COUNT(*) FILTER (WHERE data_processing_consent) AS talent_pool,

        COUNT(*) FILTER (
            WHERE NOT data_processing_consent
              AND NOT reached_hire
        ) AS lost_profiles

    FROM stage_reached
    GROUP BY source_name, source_category, cost_per_application
)

SELECT
    source_name,
    source_category,

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
        hires * 100.0 / NULLIF(applications, 0),
        2
    ) AS hire_rate_pct,

    cost_per_application,
    applications * cost_per_application AS estimated_cost_eur,

    ROUND(
        (applications * cost_per_application)::numeric
        / NULLIF(hires, 0),
        0
    ) AS cost_per_hire_eur,

    talent_pool,
    ROUND(
        talent_pool * 100.0 / NULLIF(applications, 0),
        2
    ) AS talent_pool_pct,
    lost_profiles

FROM per_source
ORDER BY cost_per_hire_eur NULLS LAST;
