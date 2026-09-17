"""Lädt data/processed nach PostgreSQL. Setzt 01_schema.sql und eine .env voraus."""

import io
import sys
from pathlib import Path

import pandas as pd
import psycopg

PROCESSED_DIR = Path("data/processed")
ENV_FILE = Path(".env")
SCHEMA = "recruiting"

LOAD_ORDER = [
    ("recruiters", "recruiters_clean.csv"),
    ("sources", "sources_clean.csv"),
    ("candidates", "candidates_clean.csv"),
    ("jobs", "jobs_clean.csv"),
    ("applications", "applications_clean.csv"),
    ("stage_events", "stage_events_clean.csv"),
    ("interviews", "interviews_clean.csv"),
    ("offers", "offers_clean.csv"),
]

EXPECTED_ROWS = {
    "recruiters": 12, "sources": 7, "candidates": 15_000, "jobs": 420,
    "applications": 20_000, "stage_events": 55_053, "interviews": 5_016,
    "offers": 648,
}

TALENT_POOL_ROWS = 18_860

DECIMAL_COLS = {"score", "difficulty_score"}


def read_env(path):
    """Liest KEY=VALUE aus einer .env, ohne zusätzliche Bibliothek."""
    settings = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        settings[key.strip()] = value.strip().strip('"').strip("'")
    return settings


def prepare(frame):
    """Wandelt Spalten so um, dass Postgres sie annimmt."""
    for column in frame.columns:
        values = frame[column]
        if (values.dtype.kind == "f"
                and column not in DECIMAL_COLS
                and values.dropna().mod(1).eq(0).all()):
            frame[column] = values.astype("Int64")
    return frame


def load_table(cursor, table, frame):
    """Schreibt eine Tabelle per COPY in die Datenbank."""
    columns = ", ".join(frame.columns)
    buffer = io.StringIO()
    frame.to_csv(buffer, index=False)
    buffer.seek(0)

    statement = (f"COPY {SCHEMA}.{table} ({columns}) "
                 f"FROM STDIN WITH (FORMAT csv, HEADER true)")
    with cursor.copy(statement) as copy:
        while chunk := buffer.read(64 * 1024):
            copy.write(chunk)


def check(cursor):
    """Vergleicht die geladenen Zeilenzahlen mit den erwarteten."""
    alles_gut = True
    for table, _ in LOAD_ORDER:
        cursor.execute(f"SELECT COUNT(*) FROM {SCHEMA}.{table}")
        actual = cursor.fetchone()[0]
        expected = EXPECTED_ROWS[table]
        status = "ok" if actual == expected else f"ERWARTET {expected}"
        alles_gut &= actual == expected
        print(f"  {table:16s} {actual:>7,} {status}".replace(",", "."))

    cursor.execute(f"SELECT COUNT(*) FROM {SCHEMA}.applications "
                   f"WHERE data_processing_consent")
    talent_pool = cursor.fetchone()[0]
    alles_gut &= talent_pool == TALENT_POOL_ROWS
    status = "ok" if talent_pool == TALENT_POOL_ROWS else f"ERWARTET {TALENT_POOL_ROWS}"
    print(f"  {'im Talentpool':16s} {talent_pool:>7,} {status}".replace(",", "."))

    return alles_gut


def main():
    settings = read_env(ENV_FILE)
    connection_string = (
        f"host={settings['DB_HOST']} port={settings['DB_PORT']} "
        f"dbname={settings['DB_NAME']} user={settings['DB_USER']} "
        f"password={settings['DB_PASSWORD']}")

    with psycopg.connect(connection_string) as connection:
        with connection.cursor() as cursor:
            print("Bestehende Inhalte entfernen")
            tables = ", ".join(f"{SCHEMA}.{name}" for name, _ in LOAD_ORDER)
            cursor.execute(f"TRUNCATE {tables}")

            print("\nLaden")
            for table, filename in LOAD_ORDER:
                frame = prepare(pd.read_csv(PROCESSED_DIR / filename, low_memory=False))
                load_table(cursor, table, frame)
                print(f"  {table:16s} {len(frame):>7,} Zeilen".replace(",", "."))

            print("\nAbnahme")
            if not check(cursor):
                connection.rollback()
                sys.exit("\nZeilenzahlen weichen ab, es wurde nichts geschrieben.")

        connection.commit()
        print("\nLaden abgeschlossen.")


if __name__ == "__main__":
    main()
