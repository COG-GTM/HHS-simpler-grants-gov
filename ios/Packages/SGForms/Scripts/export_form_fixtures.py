"""Export every registered application form to SGForms test fixtures.

Each fixture mirrors the `data` payload of `GET /alpha/forms/:form_id`
(snake_case keys, `$ref`s resolved exactly as the API registry resolves them),
so the Swift tests decode them with `JSONDecoder.sg` into `FormDefinition`.

Run from the repo root with the API environment installed (`cd api && uv sync`):

    cd api && uv run python ../ios/Packages/SGForms/Scripts/export_form_fixtures.py
"""

import json
import pathlib
import sys

from src.form_schema.forms import get_active_forms, init_form_registry

OUT_DIR = (
    pathlib.Path(__file__).resolve().parent.parent / "Tests" / "SGFormsTests" / "Fixtures" / "forms"
)
# Bundled with SGForms for previews / snapshot hosts (sample mode only).
SAMPLE_DIR = pathlib.Path(__file__).resolve().parent.parent / "Sources" / "SGForms" / "Resources" / "Samples"
SAMPLE_FORMS = ["SF424_4_0"]


def main() -> int:
    init_form_registry()
    forms = sorted(get_active_forms(), key=lambda f: f.short_form_name)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for old in OUT_DIR.glob("*.json"):
        old.unlink()

    for form in forms:
        payload = {
            "form_id": str(form.form_id),
            "form_name": form.form_name,
            "short_form_name": form.short_form_name,
            "form_version": form.form_version,
            "form_type": form.form_type.value if form.form_type else None,
            "agency_code": form.agency_code,
            "omb_number": form.omb_number,
            "form_json_schema": form.form_json_schema,
            "form_ui_schema": form.form_ui_schema,
            "form_rule_schema": form.form_rule_schema,
        }
        path = OUT_DIR / f"{form.short_form_name}.json"
        path.write_text(json.dumps(payload, indent=2, sort_keys=True, default=str) + "\n")
        print(f"exported {path.name}")

    print(f"{len(forms)} forms exported to {OUT_DIR}")
    SAMPLE_DIR.mkdir(parents=True, exist_ok=True)
    for name in SAMPLE_FORMS:
        (SAMPLE_DIR / f"{name}.json").write_text((OUT_DIR / f"{name}.json").read_text())
        print(f"copied {name}.json to {SAMPLE_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
