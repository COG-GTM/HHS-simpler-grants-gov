#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

python3 - "$IOS_DIR" "$@" <<'PY'
import argparse
import contextlib
import io
import plistlib
import re
import sys
import tempfile
from pathlib import Path


STRINGS_PATTERN = re.compile(r'"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;\s*$')
LOCALIZED_PATTERN = re.compile(r'"((?:[^"\\]|\\.)+)"\s*\.localized\b')
RAW_TEXT_PATTERN = re.compile(r'\b(?:Text|Button|Label)\s*\(\s*"((?:\\.|[^"\\])*)"')
RAW_TITLE_PATTERN = re.compile(r'\.navigationTitle\s*\(\s*"((?:\\.|[^"\\])*)"')
TEST_DIRS = {"AppTests", "AppUITests", "SnapshotTests"}


def is_skipped_directory(path):
    return (
        path.name in {".build", "DerivedData", "Design"}
        or path.name.endswith(".xcodeproj")
        or (path.parts[-2:] == ("fastlane", "output"))
    )


def files_under(root, suffix):
    for path in sorted(root.rglob(f"*{suffix}")):
        relative = path.relative_to(root)
        if any(is_skipped_directory(Path(*relative.parts[:index])) for index in range(1, len(relative.parts))):
            continue
        yield path


def mask_swift_comments(source) -> str:
    masked = list(source)
    index = 0
    block_depth = 0
    string_delimiter = None
    escaped = False
    while index < len(source):
        if block_depth:
            if source.startswith("/*", index):
                masked[index:index + 2] = [" ", " "]
                block_depth += 1
                index += 2
            elif source.startswith("*/", index):
                masked[index:index + 2] = [" ", " "]
                block_depth -= 1
                index += 2
            else:
                if source[index] not in "\r\n":
                    masked[index] = " "
                index += 1
            continue

        if string_delimiter is not None:
            if escaped:
                escaped = False
                index += 1
            elif source[index] == "\\":
                escaped = True
                index += 1
            elif string_delimiter == '"""' and source.startswith('"""', index):
                string_delimiter = None
                index += 3
            elif string_delimiter == '"' and source[index] == '"':
                string_delimiter = None
                index += 1
            else:
                index += 1
            continue

        if source.startswith('"""', index):
            string_delimiter = '"""'
            index += 3
        elif source[index] == '"':
            string_delimiter = '"'
            index += 1
        elif source.startswith("//", index):
            while index < len(source) and source[index] not in "\r\n":
                masked[index] = " "
                index += 1
        elif source.startswith("/*", index):
            masked[index:index + 2] = [" ", " "]
            block_depth = 1
            index += 2
        else:
            index += 1
    return "".join(masked)


def strip_comments(text):
    output = []
    in_block = False
    for line in text.splitlines():
        result = []
        index = 0
        in_string = False
        escaped = False
        while index < len(line):
            if in_block:
                end = line.find("*/", index)
                if end == -1:
                    index = len(line)
                else:
                    in_block = False
                    index = end + 2
                continue
            if not in_string and line.startswith("/*", index):
                in_block = True
                index += 2
                continue
            if not in_string and line.startswith("//", index):
                break
            char = line[index]
            result.append(char)
            if in_string:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == '"':
                    in_string = False
            elif char == '"':
                in_string = True
            index += 1
        output.append("".join(result))
    return output


def parse_strings(path, errors):
    keys = set()
    for line_number, line in enumerate(strip_comments(path.read_text(encoding="utf-8")), 1):
        if not line.strip():
            continue
        match = STRINGS_PATTERN.fullmatch(line.strip())
        if not match:
            errors.append(f"{path}: {line_number}: line does not parse as a .strings entry")
            continue
        key = match.group(1)
        if key in keys:
            errors.append(f"{path}: {line_number}: duplicate key {key!r}")
        keys.add(key)
    return keys


def table_groups(root):
    groups = {}
    for path in files_under(root, ".strings"):
        if path.parent.suffix != ".lproj":
            continue
        group_key = (path.parent.parent, path.name)
        groups.setdefault(group_key, {})[path.parent.stem] = path
    return groups


def swift_table(root, path, use_main):
    app_table = root / "App/Resources/Localization/en.lproj/Localizable.strings"
    if use_main or "App" in path.relative_to(root).parts:
        return app_table
    parts = path.relative_to(root).parts
    try:
        packages_index = parts.index("Packages")
        sources_index = parts.index("Sources", packages_index + 1)
        target = root.joinpath(*parts[:sources_index + 2])
    except (ValueError, IndexError):
        return None
    candidates = sorted(target.rglob("en.lproj/Localizable.strings"))
    return candidates[0] if candidates else None


def brace_delta(line):
    delta = 0
    in_string = False
    escaped = False
    index = 0
    while index < len(line):
        char = line[index]
        if not in_string and line.startswith("//", index):
            break
        if not in_string and line.startswith("/*", index):
            end = line.find("*/", index + 2)
            if end == -1:
                break
            index = end + 2
            continue
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
        elif char == '"':
            in_string = True
        elif char == "{":
            delta += 1
        elif char == "}":
            delta -= 1
        index += 1
    return delta


def preview_line_numbers(source):
    preview_lines = set()
    preview_depth = 0
    preview_pending = False
    for line_number, line in enumerate(source.splitlines(), 1):
        starts_preview = bool(re.search(r"#Preview\b", line))
        starts_provider = bool(re.search(r":\s*(?:SwiftUI\.)?PreviewProvider\b", line))
        if preview_depth > 0 or preview_pending:
            preview_lines.add(line_number)
            preview_depth += brace_delta(line)
            if preview_depth > 0:
                preview_pending = False
            else:
                preview_depth = 0
                preview_pending = False
            continue
        if starts_preview or starts_provider:
            preview_lines.add(line_number)
            preview_depth = brace_delta(line)
            preview_pending = preview_depth == 0
    return preview_lines


def is_test_source(path, root):
    parts = path.relative_to(root).parts
    return any(part in TEST_DIRS or part == "Tests" for part in parts[:-1])


def lint(root):
    errors = []
    all_tables = {}
    for group_key, languages in table_groups(root).items():
        parsed = {
            language: parse_strings(path, errors)
            for language, path in sorted(languages.items())
        }
        english = parsed.get("en")
        directory, table_name = group_key
        if english is None:
            errors.append(f"{directory}: missing en.lproj/{table_name} base table")
            continue
        for language, keys in sorted(parsed.items()):
            if language == "en":
                continue
            missing = sorted(english - keys)
            extra = sorted(keys - english)
            if missing:
                errors.append(
                    f"{languages[language]}: missing keys from en: {', '.join(missing)}"
                )
            if extra:
                errors.append(
                    f"{languages[language]}: extra keys vs en: {', '.join(extra)}"
                )
        for language, path in languages.items():
            all_tables[path.resolve()] = parsed[language]

    for path in files_under(root, ".swift"):
        if is_test_source(path, root):
            continue
        source = path.read_text(encoding="utf-8")
        masked_source = mask_swift_comments(source)
        for match in LOCALIZED_PATTERN.finditer(masked_source):
            key = match.group(1)
            line_number = masked_source.count("\n", 0, match.start()) + 1
            suffix = masked_source[match.end():]
            use_main = bool(re.match(r"\s*\(\s*bundle\s*:\s*\.main\b", suffix))
            table = swift_table(root, path, use_main)
            if table is None or not table.is_file():
                errors.append(f"{path}: {line_number}: missing localization table for key {key!r}")
                continue
            keys = all_tables.get(table.resolve())
            if keys is None:
                keys = parse_strings(table, errors)
                all_tables[table.resolve()] = keys
            if key not in keys:
                errors.append(f"{path}: {line_number}: unknown localized key {key!r} in {table}")

        preview_lines = preview_line_numbers(masked_source)
        for pattern in (RAW_TEXT_PATTERN, RAW_TITLE_PATTERN):
            for match in pattern.finditer(masked_source):
                line_number = masked_source.count("\n", 0, match.start()) + 1
                if line_number in preview_lines:
                    continue
                literal = match.group(1)
                after_literal = masked_source[match.end():]
                if re.match(r"\s*\.localized\b", after_literal):
                    continue
                without_interpolation = re.sub(r"\\\([^)]*\)", "", literal)
                if not any(character.isalpha() for character in without_interpolation):
                    continue
                errors.append(
                    f"{path}: {line_number}: user-facing string literal must be localized"
                )

    info_plist = root / "App/Info.plist"
    info_strings = root / "App/Resources/Localization/en.lproj/InfoPlist.strings"
    if info_plist.is_file():
        try:
            with info_plist.open("rb") as plist_file:
                plist = plistlib.load(plist_file)
            required = {
                key for key in plist
                if key == "CFBundleDisplayName"
                or (key.startswith("NS") and key.endswith("UsageDescription"))
            }
            if info_strings.is_file():
                keys = all_tables.get(info_strings.resolve())
                if keys is None:
                    keys = parse_strings(info_strings, errors)
                for key in sorted(required - keys):
                    errors.append(
                        f"{info_strings}: 1: missing InfoPlist localization for {key}"
                    )
            else:
                for key in sorted(required):
                    errors.append(
                        f"{info_strings}: 1: missing InfoPlist localization for {key}"
                    )
        except (OSError, plistlib.InvalidFileException, ValueError) as error:
            errors.append(f"{info_plist}: 1: could not parse property list: {error}")

    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        print(f"Localization lint failed with {len(errors)} error(s).", file=sys.stderr)
        return 1
    print("Localization lint passed.")
    return 0


def write(path, contents):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(contents, encoding="utf-8")


def fixture(root):
    write(
        root / "App/Resources/Localization/en.lproj/Localizable.strings",
        '"hello" = "Hello";\n"main.known" = "Known";\n',
    )
    write(
        root / "App/Resources/Localization/en.lproj/InfoPlist.strings",
        '"CFBundleDisplayName" = "Demo";\n',
    )
    (root / "App").mkdir(parents=True, exist_ok=True)
    (root / "App/Info.plist").write_bytes(
        plistlib.dumps({"CFBundleDisplayName": "Demo"})
    )
    write(
        root / "Packages/Pkg/Sources/Pkg/Resources/en.lproj/Localizable.strings",
        '"pkg.known" = "Package";\n',
    )
    write(root / "App/Example.swift", "struct Example { }\n")
    write(root / "Packages/Pkg/Sources/Pkg/Example.swift", "struct PackageExample { }\n")


def self_test():
    cases = [
        ("passing fixture", "pass", None),
        ("missing key in de.lproj", "de", "missing keys from en"),
        ("extra key in de.lproj", "extra", "extra keys vs en"),
        ("duplicate key", "duplicate", "duplicate key"),
        ("unknown localized key", "unknown", "unknown localized key"),
        ("raw literal in view", "raw", "user-facing string literal"),
        ("raw literal in preview", "preview", None),
        ("interpolation-only text", "interpolation", None),
        ("bundle main resolves to App table", "main", None),
        ("missing InfoPlist localization", "missing_info", "missing InfoPlist localization"),
        ("unparseable .strings line", "unparseable", "does not parse"),
        ("raw Button literal", "button", "user-facing string literal"),
        ("multiline raw literal in view", "multiline_raw", "user-facing string literal"),
        ("line comment with unknown key", "line_comment", None),
        ("block comment with unknown key", "block_comment", None),
        ("URL string and raw view literal", "url_raw", "user-facing string literal"),
        ("multiline raw literal in preview", "multiline_preview", None),
    ]
    failures = []
    with tempfile.TemporaryDirectory(prefix="ios-l10n-self-test-") as temporary:
        base = Path(temporary)
        for name, case, expected in cases:
            root = base / case
            fixture(root)
            if case == "de":
                write(
                    root / "App/Resources/Localization/de.lproj/Localizable.strings",
                    '"main.known" = "Known";\n',
                )
            elif case == "extra":
                write(
                    root / "App/Resources/Localization/de.lproj/Localizable.strings",
                    '"hello" = "Hello";\n"extra" = "Extra";\n"main.known" = "Known";\n',
                )
            elif case == "duplicate":
                write(
                    root / "App/Resources/Localization/en.lproj/Localizable.strings",
                    '"hello" = "Hello";\n"hello" = "Again";\n"main.known" = "Known";\n',
                )
            elif case == "unknown":
                write(root / "App/Example.swift", '"missing.key".localized\n')
            elif case == "raw":
                write(root / "App/Example.swift", 'var body: some View { Text("Hello") }\n')
            elif case == "preview":
                write(root / "App/Example.swift", '#Preview {\n    Text("Hello")\n}\n')
            elif case == "interpolation":
                write(root / "App/Example.swift", 'Text("\\(n)")\n')
            elif case == "main":
                write(
                    root / "Packages/Pkg/Sources/Pkg/Example.swift",
                    '"main.known".localized(bundle: .main)\n',
                )
            elif case == "missing_info":
                write(
                    root / "App/Resources/Localization/en.lproj/InfoPlist.strings",
                    '"OtherKey" = "Other";\n',
                )
            elif case == "unparseable":
                write(
                    root / "App/Resources/Localization/en.lproj/Localizable.strings",
                    '"hello" = "Hello";\nnot a valid entry\n"main.known" = "Known";\n',
                )
            elif case == "button":
                write(root / "App/Example.swift", 'var body: some View { Button("Save") {} }\n')
            elif case == "multiline_raw":
                write(root / "App/Example.swift", 'Text(\n    "Save"\n)\n')
            elif case == "line_comment":
                write(root / "App/Example.swift", '// "old.key".localized\n')
            elif case == "block_comment":
                write(root / "App/Example.swift", '/* "old.key".localized */\n')
            elif case == "url_raw":
                write(root / "App/Example.swift", 'let u = "https://x"; Text("Raw")\n')
            elif case == "multiline_preview":
                write(
                    root / "App/Example.swift",
                    '#Preview {\n    Text(\n        "Save"\n    )\n}\n',
                )

            output = io.StringIO()
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
                result = lint(root)
            diagnostics = output.getvalue()
            if expected is None:
                success = result == 0
            else:
                success = result != 0 and expected in diagnostics
            if success:
                print(f"PASS {name}")
            else:
                failures.append(name)
                print(f"FAIL {name}")
    if failures:
        print(f"Localization self-test failed: {', '.join(failures)}", file=sys.stderr)
        return 1
    return 0


parser = argparse.ArgumentParser()
parser.add_argument("--root", type=Path, default=Path(sys.argv[1]))
parser.add_argument("--self-test", action="store_true")
arguments = parser.parse_args(sys.argv[2:])
if arguments.self_test:
    raise SystemExit(self_test())
raise SystemExit(lint(arguments.root.resolve()))
PY
