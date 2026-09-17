"""Bereinigung der TalentFlow-Rohdaten.

Liest data/raw, schreibt bereinigte Tabellen nach data/processed und ein
Protokoll aller Änderungen nach docs/. Die Rohdateien bleiben unverändert.
"""

from pathlib import Path

import numpy as np
import pandas as pd

RAW_DIR = Path("data/raw")
PROCESSED_DIR = Path("data/processed")
LOG_FILE = Path("docs/cleaning_log.md")

# --- Entscheidungen ------------------------------------------------------

SALARY_MIN = 20_000
SALARY_MAX = 250_000
LOCATION_UNKNOWN = "Unbekannt"

SOURCE_MAP = {
    "career page": "Career Page", "careers page": "Career Page",
    "company website": "Career Page",
    "linkedin": "LinkedIn", "linked in": "LinkedIn",
    "indeed": "Indeed", "indeed.de": "Indeed",
    "employee referral": "Employee Referral", "referral": "Employee Referral",
    "mitarbeiterempfehlung": "Employee Referral",
    "recruiting agency": "Recruiting Agency", "agency": "Recruiting Agency",
    "recruitment agency": "Recruiting Agency",
    "federal employment agency": "Federal Employment Agency",
    "arbeitsagentur": "Federal Employment Agency",
    "bundesagentur für arbeit": "Federal Employment Agency",
    "university event": "University Event", "campus event": "University Event",
    "university fair": "University Event",
}

MILESTONES = {
    "Application Submitted": "applied_date",
    "Recruiter Screen": "screen_date",
    "Interview 1": "interview_1_date",
    "Interview 2": "interview_2_date",
    "Offer": "offer_date",
    "Hired": "hire_date",
    "Offer Declined": "offer_declined_date",
    "Rejected": "rejected_date",
    # "Withdrawn" fehlt: steht bereits als withdrawal_date im Quellexport
}

TABLES = ["applications", "candidates", "jobs", "recruiters",
          "sources", "stage_events", "interviews", "offers"]

OUTPUT_NAMES = {
    "applications": "applications_clean", "candidates": "candidates_clean",
    "jobs": "jobs_clean", "recruiters": "recruiters_clean",
    "sources": "sources_clean", "stage_events": "stage_events_clean",
    "interviews": "interviews_clean", "offers": "offers_clean",
}

DURATION_COLS = ["days_to_screen", "days_screen_to_interview",
                 "days_interview_to_offer", "days_offer_to_response", "days_to_hire"]

changes = []


def log_change(finding, decision, rows):
    changes.append({"Befund": finding, "Entscheidung": decision,
                    "Betroffene Zeilen": int(rows)})


def number(value, width=0):
    return f"{int(value):,}".replace(",", ".").rjust(width)


def percent(value, digits=2):
    return f"{value:.{digits}f}".replace(".", ",")


def markdown_table(frame):
    """Baut eine Markdown-Tabelle ohne das Zusatzpaket tabulate."""
    columns = list(frame.columns)
    lines = ["| " + " | ".join(columns) + " |",
             "|" + "|".join([" --- "] * len(columns)) + "|"]
    for row in frame.itertuples(index=False):
        lines.append("| " + " | ".join(str(value) for value in row) + " |")
    return "\n".join(lines)


def parse_dates(column):
    """Liest ISO-, deutsches und Schrägstrichformat, alles andere wird NaT."""
    result = pd.to_datetime(column, format="%Y-%m-%d", errors="coerce")
    for date_format in ("%d.%m.%Y", "%d/%m/%Y"):
        open_rows = result.isna() & column.notna()
        if open_rows.any():
            result.loc[open_rows] = pd.to_datetime(column[open_rows],
                                                   format=date_format, errors="coerce")
    return result


def load_raw():
    data = {}
    for name in TABLES:
        path = RAW_DIR / f"{name}.csv"
        if not path.exists():
            raise FileNotFoundError(f"{path} fehlt. RAW_DIR oben anpassen.")
        data[name] = pd.read_csv(path, dtype=str, keep_default_na=False, na_values=[""])
    return data


def drop_exact_duplicates(data):
    """Entfernt exakte Zeilendubletten."""
    for table, key in [("applications", "application_id"),
                       ("candidates", "candidate_id"),
                       ("stage_events", "event_id")]:
        frame = data[table]
        duplicate_keys = int(frame[key].duplicated().sum())
        duplicate_rows = int(frame.duplicated().sum())
        assert duplicate_keys == duplicate_rows, (
            f"{table}: {duplicate_keys} wiederholte {key}, aber nur "
            f"{duplicate_rows} identische Zeilen. Vor dem Löschen prüfen.")
        if duplicate_rows:
            data[table] = frame.drop_duplicates().reset_index(drop=True)
            log_change(f"{table}: wiederholte {key}",
                       "als exakte Zeilenkopien nachgewiesen, erste behalten",
                       duplicate_rows)
            print(f"  {table:14s} {duplicate_rows:3d} entfernt -> "
                  f"{number(len(data[table]))} Zeilen")
    return data


def normalize_sources(applications, sources):
    """Führt die 24 Schreibweisen auf 7 Kanäle zusammen, stellt fehlende IDs her."""
    key = applications["source_name_raw"].str.strip().str.lower()
    unknown = sorted(set(key.dropna()) - set(SOURCE_MAP))
    assert not unknown, f"Unbekannte Schreibweisen: {unknown}. SOURCE_MAP ergänzen."

    applications["source_name"] = key.map(SOURCE_MAP)
    changed = int((applications["source_name"] != applications["source_name_raw"]).sum())
    log_change("Recruiting-Quelle in 24 Schreibweisen für 7 Kanäle",
               "auf einheitliche Bezeichnung in der Spalte source_name abgebildet", changed)

    id_by_name = dict(zip(sources["source_name"], sources["source_id"]))
    missing = applications["source_id"].isna()
    applications.loc[missing, "source_id"] = (
        applications.loc[missing, "source_name"].map(id_by_name))
    log_change("fehlende source_id", "aus dem Quellennamen wiederhergestellt", missing.sum())
    assert applications["source_id"].notna().all()

    print(f"  {number(changed)} vereinheitlicht, {int(missing.sum())} IDs hergestellt")
    return applications


def check_foreign_keys(applications, data):
    """Setzt verwaiste Fremdschlüssel auf NULL und kennzeichnet die Zeile."""
    for column, parent, flag in [("candidate_id", "candidates", "has_valid_candidate"),
                                 ("job_id", "jobs", "has_valid_job")]:
        valid = applications[column].isin(data[parent][column])
        applications[flag] = valid
        applications.loc[~valid, column] = np.nan
        log_change(f"applications.{column} ohne passenden Datensatz",
                   f"auf NULL, Zeile behalten, gekennzeichnet in {flag}", (~valid).sum())
        print(f"  {column:14s} {int((~valid).sum()):3d} verwaist")
    return applications


def convert_dates(applications, jobs, recruiters, events, interviews, offers):
    """Wandelt alle Datumstexte in Datumswerte."""
    before = int(applications["application_date"].notna().sum())
    applications["application_date"] = parse_dates(applications["application_date"])
    lost = before - int(applications["application_date"].notna().sum())
    log_change("gemischte Datumsformate und nicht existierende Kalendertage",
               "drei Formate gelesen, unmögliche Tage auf NULL", lost)

    applications["withdrawal_date"] = parse_dates(applications["withdrawal_date"])
    for column in ["opening_date", "close_date"]:
        jobs[column] = parse_dates(jobs[column])
    recruiters["start_date"] = parse_dates(recruiters["start_date"])
    events["event_date"] = parse_dates(events["event_date"])
    events["stage_sequence"] = events["stage_sequence"].astype(int)
    for column in ["scheduled_date", "completed_date"]:
        interviews[column] = parse_dates(interviews[column])
    for column in ["offer_date", "response_date", "planned_start_date"]:
        offers[column] = parse_dates(offers[column])

    print(f"  {lost} nicht lesbare Bewerbungsdaten auf NULL")
    return applications, jobs, recruiters, events, interviews, offers


def check_date_order(events, interviews, offers):
    """Nullt Datumswerte, die vor ihrem Vorgänger liegen."""
    submitted = events.loc[events["stage_name"] == "Application Submitted"] \
        .set_index("application_id")["event_date"]
    wrong = (events["event_date"] < events["application_id"].map(submitted)) \
        & (events["stage_name"] != "Application Submitted")
    events["date_is_valid"] = ~wrong
    events.loc[wrong, "event_date"] = pd.NaT
    log_change("Prozessschritt liegt vor der zugehörigen Bewerbung",
               "Datum auf NULL, gekennzeichnet in date_is_valid", wrong.sum())
    print(f"  Prozessschritt vor der Bewerbung               {int(wrong.sum()):3d}")

    for frame, column, reference, finding in [
        (interviews, "completed_date", "scheduled_date", "Interview vor dem Termin abgeschlossen"),
        (offers, "response_date", "offer_date", "Angebot beantwortet vor Abgabe"),
        (offers, "planned_start_date", "response_date", "Eintritt vor der Zusage"),
    ]:
        wrong = frame[column] < frame[reference]
        frame[f"{column}_is_valid"] = ~wrong
        frame.loc[wrong, column] = pd.NaT
        log_change(finding, f"{column} auf NULL, gekennzeichnet", wrong.sum())
        print(f"  {finding:46s} {int(wrong.sum()):3d}")
    return events, interviews, offers


def clean_numerics(applications, jobs, candidates, sources, interviews, offers):
    """Wandelt Zahlenspalten um und nullt unmögliche Werte."""
    salary = pd.to_numeric(applications["salary_expectation_eur"], errors="coerce")
    implausible = (salary < SALARY_MIN) | (salary > SALARY_MAX)
    applications["salary_expectation_eur"] = salary.where(~implausible)
    applications["salary_is_plausible"] = ~implausible
    log_change(f"Gehaltswunsch außerhalb {number(SALARY_MIN)} bis {number(SALARY_MAX)} Euro",
               "als Erfassungsfehler auf NULL, nicht gekappt", implausible.sum())

    interviews["score"] = pd.to_numeric(interviews["score"], errors="coerce")
    interviews["no_show"] = interviews["no_show"].map({"True": True, "False": False})
    log_change("durchgeführtes Interview ohne Bewertung",
               "Zeile behalten, nur aus Bewertungsdurchschnitten ausgenommen",
               (interviews["score"].isna() & ~interviews["no_show"]).sum())

    for column in ["target_hires", "salary_min_eur", "salary_max_eur", "difficulty_score"]:
        jobs[column] = pd.to_numeric(jobs[column])
    for column in ["base_salary_eur", "bonus_pct"]:
        offers[column] = pd.to_numeric(offers[column])
    sources["estimated_cost_per_application_eur"] = pd.to_numeric(
        sources["estimated_cost_per_application_eur"])
    candidates["years_experience"] = pd.to_numeric(candidates["years_experience"])
    candidates["willing_to_relocate"] = candidates["willing_to_relocate"] \
        .map({"True": True, "False": False})

    without_location = int(candidates["current_location"].isna().sum())
    candidates["current_location"] = candidates["current_location"].fillna(LOCATION_UNKNOWN)
    log_change("Kandidat ohne Ortsangabe",
               f"auf '{LOCATION_UNKNOWN}' gesetzt, damit die Zeile zählbar bleibt",
               without_location)

    print(f"  {int(implausible.sum())} Gehälter genullt, {without_location} Orte gefüllt")
    return applications, jobs, candidates, sources, interviews, offers


def normalize_rejection_reasons(applications):
    """Führt Gründe zusammen, die sich nur in Schreibweise oder Leerzeichen unterscheiden."""
    original = applications["rejection_reason"]
    stripped = original.str.strip()
    frequency = stripped.dropna().value_counts()

    preferred = {}
    for value, count in frequency.items():
        lowered = value.lower()
        if lowered not in preferred or count > frequency[preferred[lowered]]:
            preferred[lowered] = value

    applications["rejection_reason"] = stripped.str.lower().map(preferred)
    changed = int(((original != applications["rejection_reason"]) & original.notna()).sum())
    log_change("Ablehnungsgrund unterscheidet sich nur in Schreibweise oder Leerzeichen",
               "auf die häufigste vorhandene Schreibweise vereinheitlicht", changed)
    print(f"  {changed} Gründe vereinheitlicht")
    return applications


def normalize_consent(applications):
    """Wandelt die Einwilligung in einen Wahrheitswert um."""
    # Einwilligung steuert nur den Talentpool, nicht die Auswertung des Verfahrens
    applications["data_processing_consent"] = applications["data_processing_consent"] \
        .map({"True": True, "False": False})
    missing = int((~applications["data_processing_consent"]).sum())
    log_change("Bewerbung ohne Einwilligung in die Aufbewahrung",
               "bleibt in allen Prozessauswertungen, die Einwilligung steuert nur "
               "die Aufnahme in den Talentpool",
               missing)
    print(f"  {number(missing)} ohne Einwilligung für den Talentpool")
    return applications


def build_milestones(applications, events):
    """Dreht die Prozessschritte auf eine Zeile je Bewerbung und berechnet Teildauern."""
    milestones = events.pivot_table(index="application_id", columns="stage_name",
                                    values="event_date", aggfunc="min")
    # nur zugeordnete Schritte, sonst landen Rohnamen als Spalten in applications
    milestones = milestones[[c for c in milestones.columns if c in MILESTONES]]
    applications = applications.merge(milestones.rename(columns=MILESTONES),
                                      left_on="application_id", right_index=True, how="left")

    applications["days_to_screen"] = (
        applications["screen_date"] - applications["applied_date"]).dt.days
    applications["days_screen_to_interview"] = (
        applications["interview_1_date"] - applications["screen_date"]).dt.days
    applications["days_interview_to_offer"] = (
        applications["offer_date"] - applications["interview_1_date"]).dt.days
    applications["days_offer_to_response"] = (
        applications[["hire_date", "offer_declined_date"]].min(axis=1)
        - applications["offer_date"]).dt.days
    applications["days_to_hire"] = (
        applications["hire_date"] - applications["applied_date"]).dt.days

    negative = int(applications[DURATION_COLS].lt(0).sum().sum())
    assert negative == 0, f"{negative} negative Dauern. Schritt 5 hat nicht alles erwischt."
    print(f"  Meilensteine gebildet, {len(DURATION_COLS)} Teildauern, keine negative Dauer")
    return applications


def write_output(results):
    """Schreibt bereinigte Tabellen und Protokoll."""
    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    for source_name, frame in results.items():
        target = PROCESSED_DIR / f"{OUTPUT_NAMES[source_name]}.csv"
        frame.to_csv(target, index=False)
        print(f"  {target.name:30s} {number(frame.shape[0], 7)} x {frame.shape[1]:>2}")

    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    frame = pd.DataFrame(changes)
    LOG_FILE.write_text(
        "# Bereinigungsprotokoll\n\n"
        "Jede Änderung an den Rohdaten mit Begründung und Zeilenzahl.\n"
        "Die Rohdateien bleiben unverändert.\n\n"
        + markdown_table(frame) + "\n", encoding="utf-8")
    print(f"  {LOG_FILE}, {len(frame)} Einträge")


def check_result(applications):
    """Plausibilitätsprüfung der bereinigten Daten."""
    base = applications
    hires = int((base["application_status"] == "Hired").sum())
    offers = int(base["offer_date"].notna().sum())
    talent_pool = int(base["data_processing_consent"].sum())

    print(f"  Bewerbungen gesamt         {number(len(base), 8)}")
    print(f"  davon im Talentpool        {number(talent_pool, 8)}")
    print(f"  Screening erreicht         {number(base['screen_date'].notna().sum(), 8)}")
    print(f"  Interview erreicht         {number(base['interview_1_date'].notna().sum(), 8)}")
    print(f"  Angebot erhalten           {number(offers, 8)}")
    print(f"  eingestellt                {number(hires, 8)}")
    print(f"  Einstellungsquote          {percent(hires / len(base) * 100):>8} %")
    print(f"  Angebotsannahmequote       {percent(hires / offers * 100, 1):>8} %")
    print(f"  Time-to-Hire Median        {base['days_to_hire'].median():>8.0f} Tage")
    for name, value in base[DURATION_COLS[:4]].median().items():
        print(f"  {name:30s} {value:>5.0f} Tage")


def main():
    print("Rohdaten einlesen")
    data = load_raw()
    for name, frame in data.items():
        print(f"  {name:14s} {number(frame.shape[0], 7)} x {frame.shape[1]:>2}")

    print("\n1 Dubletten")
    data = drop_exact_duplicates(data)

    applications = data["applications"].copy()
    candidates = data["candidates"].copy()
    jobs = data["jobs"].copy()
    recruiters = data["recruiters"].copy()
    sources = data["sources"].copy()
    events = data["stage_events"].copy()
    interviews = data["interviews"].copy()
    offers = data["offers"].copy()

    print("\n2 Recruiting-Quellen")
    applications = normalize_sources(applications, sources)

    print("\n3 Fremdschlüssel")
    applications = check_foreign_keys(applications, data)

    print("\n4 Datumsspalten")
    applications, jobs, recruiters, events, interviews, offers = convert_dates(
        applications, jobs, recruiters, events, interviews, offers)

    print("\n5 Unmögliche Reihenfolgen")
    events, interviews, offers = check_date_order(events, interviews, offers)

    print("\n6 Zahlenfelder")
    applications, jobs, candidates, sources, interviews, offers = clean_numerics(
        applications, jobs, candidates, sources, interviews, offers)

    print("\n7 Ablehnungsgründe")
    applications = normalize_rejection_reasons(applications)

    print("\n8 Einwilligung")
    applications = normalize_consent(applications)

    print("\n9 Meilensteine und Dauern")
    applications = build_milestones(applications, events)

    print("\n10 Ergebnis schreiben")
    write_output({
        "applications": applications, "candidates": candidates, "jobs": jobs,
        "recruiters": recruiters, "sources": sources, "stage_events": events,
        "interviews": interviews, "offers": offers,
    })

    print("\n11 Plausibilitätsprüfung")
    check_result(applications)


if __name__ == "__main__":
    main()
