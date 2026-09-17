WITH stage_reached AS (
    SELECT
        app.application_id,

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

    LEFT JOIN recruiting.stage_events AS event
        ON app.application_id = event.application_id

    GROUP BY
        app.application_id,
        app.rejection_reason
),

funnel AS (
    SELECT
        1 AS stage_order,
        'Applications' AS stage,
        COUNT(*) AS applications,
        NULL::bigint AS blocked_by_filled_position
    FROM stage_reached

    UNION ALL

    SELECT
        2,
        'Screenings',
        COUNT(*) FILTER (WHERE reached_screening),
        NULL::bigint
    FROM stage_reached

    UNION ALL

    SELECT
        3,
        'Interviews',
        COUNT(*) FILTER (WHERE reached_interview),
        NULL::bigint
    FROM stage_reached

    UNION ALL

    SELECT
        4,
        'Offers',
        COUNT(*) FILTER (WHERE reached_offer),
        COUNT(*) FILTER (
            WHERE reached_interview
              AND blocked_by_filled_position
        )
    FROM stage_reached

    UNION ALL

    SELECT
        5,
        'Hires',
        COUNT(*) FILTER (WHERE reached_hire),
        NULL::bigint
    FROM stage_reached
),

funnel_calculations AS (
    SELECT
        stage_order,
        stage,
        applications,
        blocked_by_filled_position,

        LAG(applications) OVER (
            ORDER BY stage_order
        ) AS previous_stage_applications,

        FIRST_VALUE(applications) OVER (
            ORDER BY stage_order
        ) AS total_applications

    FROM funnel
)

SELECT
    stage_order,
    stage,
    applications,

    previous_stage_applications - applications
        AS drop_off,

    blocked_by_filled_position
        AS drop_off_position_filled,

    ROUND(
        applications * 100.0
        / NULLIF(previous_stage_applications, 0),
        2
    ) AS conversion_from_previous_stage_pct,

    ROUND(
        applications * 100.0
        / NULLIF(
            previous_stage_applications
            - COALESCE(blocked_by_filled_position, 0),
            0
        ),
        2
    ) AS conversion_adjusted_pct,

    ROUND(
        applications * 100.0
        / NULLIF(total_applications, 0),
        2
    ) AS conversion_from_application_pct

FROM funnel_calculations
ORDER BY stage_order;
