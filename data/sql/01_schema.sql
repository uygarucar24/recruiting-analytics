DROP TABLE IF EXISTS recruiting.offers        CASCADE;
DROP TABLE IF EXISTS recruiting.interviews    CASCADE;
DROP TABLE IF EXISTS recruiting.stage_events  CASCADE;
DROP TABLE IF EXISTS recruiting.applications  CASCADE;
DROP TABLE IF EXISTS recruiting.jobs          CASCADE;
DROP TABLE IF EXISTS recruiting.candidates    CASCADE;
DROP TABLE IF EXISTS recruiting.sources       CASCADE;
DROP TABLE IF EXISTS recruiting.recruiters    CASCADE;

CREATE SCHEMA IF NOT EXISTS recruiting;

CREATE TABLE recruiting.recruiters (
    recruiter_id      text    NOT NULL,
    recruiter_name    text    NOT NULL,
    experience_level  text    NOT NULL,
    specialization    text    NOT NULL,
    office            text    NOT NULL,
    start_date        date    NOT NULL,

    CONSTRAINT pk_recruiters PRIMARY KEY (recruiter_id)
);

CREATE TABLE recruiting.sources (
    source_id                          text     NOT NULL,
    source_name                        text     NOT NULL,
    source_category                    text     NOT NULL,
    estimated_cost_per_application_eur integer  NOT NULL,

    CONSTRAINT pk_sources PRIMARY KEY (source_id),
    CONSTRAINT uq_sources_name UNIQUE (source_name),
    CONSTRAINT chk_sources_cost CHECK (estimated_cost_per_application_eur >= 0)
);

CREATE TABLE recruiting.candidates (
    candidate_id          text     NOT NULL,
    age_group             text     NOT NULL,
    years_experience      integer  NOT NULL,
    education_level       text     NOT NULL,
    current_location      text     NOT NULL,
    willing_to_relocate   boolean  NOT NULL,
    preferred_work_model  text     NOT NULL,

    CONSTRAINT pk_candidates PRIMARY KEY (candidate_id),
    CONSTRAINT chk_candidates_experience CHECK (years_experience BETWEEN 0 AND 60)
);

CREATE TABLE recruiting.jobs (
    job_id            text          NOT NULL,
    job_title         text          NOT NULL,
    department        text          NOT NULL,
    location          text          NOT NULL,
    country           text          NOT NULL,
    seniority         text          NOT NULL,
    employment_type   text          NOT NULL,
    work_model        text          NOT NULL,
    opening_date      date          NOT NULL,
    target_hires      integer       NOT NULL,
    job_status        text          NOT NULL,
    close_date        date,
    recruiter_id      text          NOT NULL,
    salary_min_eur    integer       NOT NULL,
    salary_max_eur    integer       NOT NULL,
    difficulty_score  numeric(2,1)  NOT NULL,

    CONSTRAINT pk_jobs PRIMARY KEY (job_id),

    CONSTRAINT fk_jobs_recruiter FOREIGN KEY (recruiter_id)
        REFERENCES recruiting.recruiters (recruiter_id),

    CONSTRAINT chk_jobs_status CHECK (job_status IN (
        'Open', 'Filled', 'Partially filled', 'Closed without hire', 'Cancelled')),
    CONSTRAINT chk_jobs_work_model CHECK (work_model IN ('On-site', 'Hybrid', 'Remote')),
    CONSTRAINT chk_jobs_seniority CHECK (seniority IN ('Junior', 'Professional', 'Senior', 'Lead')),
    CONSTRAINT chk_jobs_target_hires CHECK (target_hires >= 1),
    CONSTRAINT chk_jobs_salary_range CHECK (salary_max_eur >= salary_min_eur),
    CONSTRAINT chk_jobs_difficulty CHECK (difficulty_score BETWEEN 1.0 AND 5.0),
    CONSTRAINT chk_jobs_close_after_open CHECK (close_date IS NULL OR close_date >= opening_date)
);

CREATE TABLE recruiting.applications (
    application_id            text     NOT NULL,
    candidate_id              text,
    job_id                    text,
    source_id                 text     NOT NULL,

    source_name_raw           text     NOT NULL,
    source_name               text     NOT NULL,

    application_date          date,
    application_status        text     NOT NULL,
    last_stage                text     NOT NULL,
    rejection_reason          text,
    withdrawal_date           date,
    salary_expectation_eur    integer,
    data_processing_consent   boolean  NOT NULL,

    has_valid_candidate       boolean  NOT NULL,
    has_valid_job             boolean  NOT NULL,
    salary_is_plausible       boolean  NOT NULL,

    applied_date              date     NOT NULL,
    screen_date               date,
    interview_1_date          date,
    interview_2_date          date,
    offer_date                date,
    offer_declined_date       date,
    hire_date                 date,
    rejected_date             date,

    days_to_screen            integer,
    days_screen_to_interview  integer,
    days_interview_to_offer   integer,
    days_offer_to_response    integer,
    days_to_hire              integer,

    CONSTRAINT pk_applications PRIMARY KEY (application_id),

    CONSTRAINT fk_applications_candidate FOREIGN KEY (candidate_id)
        REFERENCES recruiting.candidates (candidate_id),
    CONSTRAINT fk_applications_job FOREIGN KEY (job_id)
        REFERENCES recruiting.jobs (job_id),
    CONSTRAINT fk_applications_source FOREIGN KEY (source_id)
        REFERENCES recruiting.sources (source_id),

    CONSTRAINT chk_applications_status CHECK (application_status IN (
        'In process', 'Rejected', 'Withdrawn', 'Offer declined', 'Hired')),
    CONSTRAINT chk_applications_last_stage CHECK (last_stage IN (
        'Application', 'Screening', 'Interview', 'Offer', 'Hired')),
    CONSTRAINT chk_applications_rejection_reason CHECK (
        rejection_reason IS NULL OR rejection_reason IN (
            'Minimum requirements not met', 'Experience mismatch', 'Skills mismatch',
            'Technical skills', 'Interview evaluation', 'Salary expectations',
            'Location', 'Team fit', 'Position already filled', 'Position cancelled')),

    CONSTRAINT chk_applications_flag_candidate CHECK (
        has_valid_candidate = (candidate_id IS NOT NULL)),
    CONSTRAINT chk_applications_flag_job CHECK (
        has_valid_job = (job_id IS NOT NULL)),

    CONSTRAINT chk_applications_salary CHECK (
        salary_expectation_eur IS NULL
        OR salary_expectation_eur BETWEEN 20000 AND 250000),

    CONSTRAINT chk_applications_screen_order CHECK (
        screen_date IS NULL OR screen_date >= applied_date),
    CONSTRAINT chk_applications_interview1_order CHECK (
        interview_1_date IS NULL OR screen_date IS NULL OR interview_1_date >= screen_date),
    CONSTRAINT chk_applications_interview2_order CHECK (
        interview_2_date IS NULL OR interview_1_date IS NULL OR interview_2_date >= interview_1_date),
    CONSTRAINT chk_applications_offer_order CHECK (
        offer_date IS NULL OR interview_1_date IS NULL OR offer_date >= interview_1_date),
    CONSTRAINT chk_applications_hire_order CHECK (
        hire_date IS NULL OR offer_date IS NULL OR hire_date >= offer_date),
    CONSTRAINT chk_applications_declined_order CHECK (
        offer_declined_date IS NULL OR offer_date IS NULL OR offer_declined_date >= offer_date),
    CONSTRAINT chk_applications_rejected_order CHECK (
        rejected_date IS NULL OR rejected_date >= applied_date),
    CONSTRAINT chk_applications_withdrawn_order CHECK (
        withdrawal_date IS NULL OR withdrawal_date >= applied_date),

    CONSTRAINT chk_applications_durations CHECK (
        COALESCE(days_to_screen, 0)           >= 0
        AND COALESCE(days_screen_to_interview, 0) >= 0
        AND COALESCE(days_interview_to_offer, 0)  >= 0
        AND COALESCE(days_offer_to_response, 0)   >= 0
        AND COALESCE(days_to_hire, 0)             >= 0)
);

CREATE TABLE recruiting.stage_events (
    event_id        text     NOT NULL,
    application_id  text     NOT NULL,
    stage_name      text     NOT NULL,
    event_date      date,
    stage_sequence  integer  NOT NULL,
    date_is_valid   boolean  NOT NULL,

    CONSTRAINT pk_stage_events PRIMARY KEY (event_id),

    CONSTRAINT fk_stage_events_application FOREIGN KEY (application_id)
        REFERENCES recruiting.applications (application_id),

    CONSTRAINT uq_stage_events_application_stage UNIQUE (application_id, stage_name),

    CONSTRAINT chk_stage_events_name CHECK (stage_name IN (
        'Application Submitted', 'Recruiter Screen', 'Interview 1', 'Interview 2',
        'Offer', 'Hired', 'Offer Declined', 'Rejected', 'Withdrawn')),
    CONSTRAINT chk_stage_events_sequence CHECK (stage_sequence BETWEEN 1 AND 6),
    CONSTRAINT chk_stage_events_flag CHECK (date_is_valid = (event_date IS NOT NULL))
);

CREATE TABLE recruiting.interviews (
    interview_id             text          NOT NULL,
    application_id           text          NOT NULL,
    interview_round          integer       NOT NULL,
    scheduled_date           date          NOT NULL,
    completed_date           date,
    interview_format         text          NOT NULL,
    interviewer_role         text          NOT NULL,
    score                    numeric(2,1),
    recommendation           text          NOT NULL,
    no_show                  boolean       NOT NULL,
    completed_date_is_valid  boolean       NOT NULL,

    CONSTRAINT pk_interviews PRIMARY KEY (interview_id),

    CONSTRAINT fk_interviews_application FOREIGN KEY (application_id)
        REFERENCES recruiting.applications (application_id),

    CONSTRAINT uq_interviews_application_round UNIQUE (application_id, interview_round),

    CONSTRAINT chk_interviews_round CHECK (interview_round IN (1, 2)),
    CONSTRAINT chk_interviews_format CHECK (interview_format IN ('On-site', 'Video', 'Phone')),
    CONSTRAINT chk_interviews_recommendation CHECK (recommendation IN ('Proceed', 'Hold', 'Reject')),
    CONSTRAINT chk_interviews_score CHECK (score IS NULL OR score BETWEEN 1.0 AND 5.0),
    CONSTRAINT chk_interviews_completed_order CHECK (
        completed_date IS NULL OR completed_date >= scheduled_date)
);

CREATE TABLE recruiting.offers (
    offer_id                     text     NOT NULL,
    application_id               text     NOT NULL,
    offer_date                   date     NOT NULL,
    base_salary_eur              integer  NOT NULL,
    bonus_pct                    integer  NOT NULL,
    offer_status                 text     NOT NULL,
    response_date                date,
    decline_reason               text,
    planned_start_date           date,
    response_date_is_valid       boolean  NOT NULL,
    planned_start_date_is_valid  boolean  NOT NULL,

    CONSTRAINT pk_offers PRIMARY KEY (offer_id),

    CONSTRAINT fk_offers_application FOREIGN KEY (application_id)
        REFERENCES recruiting.applications (application_id),
    CONSTRAINT uq_offers_application UNIQUE (application_id),

    CONSTRAINT chk_offers_status CHECK (offer_status IN ('Accepted', 'Declined')),
    CONSTRAINT chk_offers_bonus CHECK (bonus_pct BETWEEN 0 AND 100),
    CONSTRAINT chk_offers_salary CHECK (base_salary_eur BETWEEN 20000 AND 250000),
    CONSTRAINT chk_offers_decline_reason CHECK (
        decline_reason IS NULL OR decline_reason IN (
            'Compensation', 'Location', 'Accepted another offer',
            'Personal reasons', 'Role scope')),
    CONSTRAINT chk_offers_response_order CHECK (
        response_date IS NULL OR response_date >= offer_date),
    CONSTRAINT chk_offers_start_order CHECK (
        planned_start_date IS NULL OR response_date IS NULL
        OR planned_start_date >= response_date)
);

CREATE INDEX idx_applications_job         ON recruiting.applications (job_id);
CREATE INDEX idx_applications_candidate   ON recruiting.applications (candidate_id);
CREATE INDEX idx_applications_source      ON recruiting.applications (source_id);
CREATE INDEX idx_applications_consent     ON recruiting.applications (data_processing_consent);
CREATE INDEX idx_stage_events_application ON recruiting.stage_events (application_id);
CREATE INDEX idx_stage_events_stage       ON recruiting.stage_events (stage_name);
CREATE INDEX idx_interviews_application   ON recruiting.interviews (application_id);
CREATE INDEX idx_jobs_recruiter           ON recruiting.jobs (recruiter_id);

SELECT 'recruiters'             AS tabelle, COUNT(*) AS zeilen FROM recruiting.recruiters
UNION ALL SELECT 'sources',             COUNT(*) FROM recruiting.sources
UNION ALL SELECT 'candidates',          COUNT(*) FROM recruiting.candidates
UNION ALL SELECT 'jobs',                COUNT(*) FROM recruiting.jobs
UNION ALL SELECT 'applications',        COUNT(*) FROM recruiting.applications
UNION ALL SELECT 'stage_events',        COUNT(*) FROM recruiting.stage_events
UNION ALL SELECT 'interviews',          COUNT(*) FROM recruiting.interviews
UNION ALL SELECT 'offers',              COUNT(*) FROM recruiting.offers
UNION ALL SELECT 'davon im Talentpool',  COUNT(*) FROM recruiting.applications
          WHERE data_processing_consent;
