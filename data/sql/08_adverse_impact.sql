WITH base AS (
    SELECT
        COALESCE(cand.age_group, 'Unbekannt') AS age_group,
        app.application_id,

        COALESCE(
            BOOL_OR(event.stage_name = 'Recruiter Screen'), FALSE
        ) AS reached_screening,

        COALESCE(
            BOOL_OR(event.stage_name IN ('Interview 1', 'Interview 2')), FALSE
        ) AS reached_interview,

        COALESCE(
            BOOL_OR(event.stage_name = 'Offer'), FALSE
        ) AS reached_offer,

        COALESCE(
            BOOL_OR(event.stage_name = 'Hired'), FALSE
        ) AS reached_hire

    FROM recruiting.applications AS app

    LEFT JOIN recruiting.candidates AS cand
        ON app.candidate_id = cand.candidate_id

    LEFT JOIN recruiting.stage_events AS event
        ON app.application_id = event.application_id

    GROUP BY
        COALESCE(cand.age_group, 'Unbekannt'),
        app.application_id
),

per_group AS (
    SELECT
        age_group,
        COUNT(*) AS applications,
        COUNT(*) FILTER (WHERE reached_screening) AS screenings,
        COUNT(*) FILTER (WHERE reached_interview) AS interviews,
        COUNT(*) FILTER (WHERE reached_offer)     AS offers,
        COUNT(*) FILTER (WHERE reached_hire)      AS hires
    FROM base
    GROUP BY age_group
),

reference AS (
    SELECT
        SUM(applications) AS total_applications,
        SUM(hires)        AS total_hires,
        SUM(hires)::numeric / SUM(applications) AS overall_hire_rate
    FROM per_group
    WHERE age_group <> 'Unbekannt'
),

rates AS (
    SELECT
        grp.age_group,
        grp.applications,
        grp.screenings,
        grp.interviews,
        grp.offers,
        grp.hires,

        ROUND(grp.screenings * 100.0 / grp.applications, 2) AS screen_rate_pct,
        ROUND(grp.hires      * 100.0 / grp.applications, 2) AS hire_rate_pct,

        ROUND(
            (grp.screenings::numeric / grp.applications)
            / MAX(grp.screenings::numeric / grp.applications)
                  FILTER (WHERE grp.age_group <> 'Unbekannt') OVER (),
            2
        ) AS impact_ratio_screening,

        ROUND(
            (grp.hires::numeric / grp.applications)
            / MAX(grp.hires::numeric / grp.applications)
                  FILTER (WHERE grp.age_group <> 'Unbekannt') OVER (),
            2
        ) AS impact_ratio_hire,

        ROUND(grp.applications * ref.overall_hire_rate, 1) AS expected_hires,

        CASE WHEN grp.age_group = 'Unbekannt' THEN NULL ELSE
            POWER(grp.hires - grp.applications * ref.overall_hire_rate, 2)
                / (grp.applications * ref.overall_hire_rate)
            + POWER(
                (grp.applications - grp.hires)
                - grp.applications * (1 - ref.overall_hire_rate), 2)
                / (grp.applications * (1 - ref.overall_hire_rate))
        END AS chi_square_part

    FROM per_group AS grp
    CROSS JOIN reference AS ref
)

SELECT
    age_group,
    applications,
    screenings,
    interviews,
    offers,
    hires,

    screen_rate_pct,
    impact_ratio_screening,

    hire_rate_pct,
    impact_ratio_hire,

    expected_hires,
    ROUND(hires - expected_hires, 1) AS difference_to_expected,

    ROUND(SUM(chi_square_part) OVER ()::numeric, 2) AS chi_square_total,

    CASE
        WHEN SUM(chi_square_part) OVER () > 7.815
        THEN 'signifikant bei 5 %'
        ELSE 'nicht signifikant bei 5 %'
    END AS chi_square_result

FROM rates
ORDER BY
    (age_group = 'Unbekannt'),
    age_group;
