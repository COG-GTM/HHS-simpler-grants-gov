"""Export the API's resolved form definitions for the iOS sample package.

Run from the API directory with:
    uv run python ../ios/Packages/SGSampleData/Scripts/export_forms.py
"""

import json
from pathlib import Path
from typing import Any

from src.form_schema.forms import init_form_registry
from src.form_schema.forms import project_narrative_attachment
from src.form_schema.forms import project_performance_site_location
from src.form_schema.forms import sf424
from src.form_schema.forms import sf424a
from src.form_schema.forms import sf424b
from src.form_schema.forms import sflll
from src.form_schema.jsonschema_resolver import resolve_jsonschema


ROOT = Path(__file__).resolve().parents[1] / "Sources/SGSampleData/Resources/Forms"
FORM_MODULES = (
    ("sf424", sf424, "SF424_v4_0"),
    ("sf424a", sf424a, "SF424a_v1_0"),
    ("sf424b", sf424b, "SF424b_v1_1"),
    ("project_narrative_attachment", project_narrative_attachment, "ProjectNarrativeAttachment_v1_2"),
    ("sflll", sflll, "SFLLL_v2_0"),
    (
        "project_performance_site_location",
        project_performance_site_location,
        "ProjectPerformanceSiteLocation_v4_0",
    ),
)


def contains_ref(value: Any) -> bool:
    if isinstance(value, dict):
        return "$ref" in value or any(contains_ref(item) for item in value.values())
    if isinstance(value, list):
        return any(contains_ref(item) for item in value)
    return False


def main() -> None:
    init_form_registry()
    ROOT.mkdir(parents=True, exist_ok=True)
    for short_name, module, attribute in FORM_MODULES:
        form = getattr(module, attribute)
        schema = resolve_jsonschema(form.form_json_schema)
        if contains_ref(schema):
            raise AssertionError(f"Unresolved $ref in {short_name}")
        payload = {
            "form_id": str(form.form_id),
            "form_name": form.form_name,
            "short_form_name": form.short_form_name,
            "form_version": form.form_version,
            "form_type": getattr(form.form_type, "value", form.form_type),
            "agency_code": form.agency_code,
            "omb_number": form.omb_number,
            "form_json_schema": schema,
            "form_ui_schema": form.form_ui_schema,
            "form_rule_schema": form.form_rule_schema,
        }
        (ROOT / f"{short_name}.json").write_text(
            json.dumps(payload, indent=2, sort_keys=True, default=str) + "\n",
            encoding="utf-8",
        )


if __name__ == "__main__":
    main()
