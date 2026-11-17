"""Summarize migration checks without printing or exporting workbook records."""

import argparse
from collections import Counter
from datetime import date, datetime
import json
from pathlib import Path

from openpyxl import load_workbook


def normalized(value):
    return str(value or "").strip()


def rows(sheet, header_row):
    values = sheet.iter_rows(min_row=header_row, values_only=True)
    headers = [normalized(value).casefold() for value in next(values)]
    return (dict(zip(headers, record)) for record in values)


def statuses(records):
    return dict(sorted(Counter(normalized(row.get("status")) or "(blank)" for row in records).items()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", nargs="?", type=Path, default=Path.cwd())
    args = parser.parse_args()
    with_workbooks = {
        "helpdesk": args.directory / "Helpdesk Records.xlsx",
        "register": args.directory / "Landscape Complaint Tracking Register - Renin.xlsx",
    }
    helpdesk = load_workbook(with_workbooks["helpdesk"], read_only=True, data_only=True)
    register = load_workbook(with_workbooks["register"], read_only=True, data_only=True)
    try:
        jobs = [row for row in rows(helpdesk["AMC Projects List"], 3) if normalized(row["job no."])]
        log = [row for row in rows(helpdesk["RM Log"], 3) if normalized(row["description of rm"])]
        complaints = [row for row in rows(register["Complaint Register"], 1) if normalized(row["complaint details"])]
        refs = Counter(normalized(row["rm ref. no."]).casefold() for row in log if normalized(row["rm ref. no."]))
        report = {
            "job_reference_rows": len(jobs),
            "rm_log_rows_with_description": len(log),
            "duplicate_rm_reference_groups": sum(count > 1 for count in refs.values()),
            "rm_log_statuses": statuses(log),
            "complaint_register_rows_with_details": len(complaints),
            "complaint_register_statuses": statuses(complaints),
            "closed_without_valid_closing_date": sum(
                normalized(row["status"]).casefold() == "closed"
                and not isinstance(row["actual closing date"], (date, datetime))
                for row in complaints
            ),
        }
        print(json.dumps(report, indent=2))
    finally:
        helpdesk.close()
        register.close()


if __name__ == "__main__":
    main()
