# Bereinigungsprotokoll

Jede Änderung an den Rohdaten mit Begründung und Zeilenzahl.
Die Rohdateien bleiben unverändert.

| Befund | Entscheidung | Betroffene Zeilen |
| --- | --- | --- |
| applications: wiederholte application_id | als exakte Zeilenkopien nachgewiesen, erste behalten | 45 |
| candidates: wiederholte candidate_id | als exakte Zeilenkopien nachgewiesen, erste behalten | 15 |
| stage_events: wiederholte event_id | als exakte Zeilenkopien nachgewiesen, erste behalten | 25 |
| Recruiting-Quelle in 24 Schreibweisen für 7 Kanäle | auf einheitliche Bezeichnung in der Spalte source_name abgebildet | 1821 |
| fehlende source_id | aus dem Quellennamen wiederhergestellt | 30 |
| applications.candidate_id ohne passenden Datensatz | auf NULL, Zeile behalten, gekennzeichnet in has_valid_candidate | 15 |
| applications.job_id ohne passenden Datensatz | auf NULL, Zeile behalten, gekennzeichnet in has_valid_job | 10 |
| gemischte Datumsformate und nicht existierende Kalendertage | drei Formate gelesen, unmögliche Tage auf NULL | 12 |
| Prozessschritt liegt vor der zugehörigen Bewerbung | Datum auf NULL, gekennzeichnet in date_is_valid | 30 |
| Interview vor dem Termin abgeschlossen | completed_date auf NULL, gekennzeichnet | 30 |
| Angebot beantwortet vor Abgabe | response_date auf NULL, gekennzeichnet | 25 |
| Eintritt vor der Zusage | planned_start_date auf NULL, gekennzeichnet | 15 |
| Gehaltswunsch außerhalb 20.000 bis 250.000 Euro | als Erfassungsfehler auf NULL, nicht gekappt | 16 |
| durchgeführtes Interview ohne Bewertung | Zeile behalten, nur aus Bewertungsdurchschnitten ausgenommen | 75 |
| Kandidat ohne Ortsangabe | auf 'Unbekannt' gesetzt, damit die Zeile zählbar bleibt | 120 |
| Ablehnungsgrund unterscheidet sich nur in Schreibweise oder Leerzeichen | auf die häufigste vorhandene Schreibweise vereinheitlicht | 90 |
| Bewerbung ohne Einwilligung in die Aufbewahrung | bleibt in allen Prozessauswertungen, die Einwilligung steuert nur die Aufnahme in den Talentpool | 1140 |
