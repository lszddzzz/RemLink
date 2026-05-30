#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import sys
import tempfile


def quote(value):
  text = str(value or "")
  return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def first_string(record, keys):
  for key in keys:
    value = record.get(key)
    if isinstance(value, str):
      return value
    if value is not None:
      return str(value)
  return ""


def first_string_list(record, keys):
  for key in keys:
    value = record.get(key)
    if isinstance(value, list):
      return [str(item) for item in value if str(item)]
  return []


def extract_records(obj):
  if isinstance(obj, list):
    return [item for item in obj if isinstance(item, dict)]
  if isinstance(obj, dict):
    for key in ("reminders", "items", "data"):
      if key in obj:
        records = extract_records(obj[key])
        if records:
          return records
  return []


def make_yaml(links):
  lines = ["links:"]
  for link in links:
    lines.append(f"  - title: {quote(link['title'])}")
    lines.append(f"    url: {quote(link['url'])}")
    lines.append("    tags:")
    if link["tags"]:
      for tag in link["tags"]:
        lines.append(f"      - {quote(tag)}")
    else:
      lines.append("      []")
    if link["note"]:
      lines.append("    note: |-")
      for note_line in link["note"].splitlines():
        lines.append(f"      {note_line}")
    else:
      lines.append('    note: ""')
  return "\n".join(lines) + "\n"


def export_json(rem, list_name):
  with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
    tmp_path = tmp.name
  try:
    subprocess.run(
      [
        rem,
        "export",
        "--list",
        list_name,
        "--format",
        "json",
        "--output-file",
        tmp_path,
      ],
      check=True,
      stdout=subprocess.PIPE,
      stderr=subprocess.PIPE,
      text=True,
    )
    with open(tmp_path, "r", encoding="utf-8") as f:
      return json.load(f)
  finally:
    try:
      os.remove(tmp_path)
    except OSError:
      pass


def main():
  parser = argparse.ArgumentParser()
  parser.add_argument("--list", default="链接")
  parser.add_argument("--output-dir", required=True)
  parser.add_argument("--rem", action="append", default=[])
  args = parser.parse_args()

  rems = []
  for rem in args.rem:
    if rem and os.path.isfile(rem) and os.access(rem, os.X_OK) and rem not in rems:
      rems.append(rem)

  if not rems:
    print("No executable rem found", file=sys.stderr)
    return 1

  errors = []
  data = None
  used_rem = None
  for rem in rems:
    try:
      data = export_json(rem, args.list)
      used_rem = rem
      break
    except subprocess.CalledProcessError as exc:
      errors.append(f"{rem}: {exc.stderr or exc.stdout or exc}")

  if data is None:
    print("\n".join(errors), file=sys.stderr)
    return 1

  links = []
  for record in extract_records(data):
    url = first_string(record, ("url", "URL", "link"))
    if not url:
      continue
    links.append(
      {
        "title": first_string(record, ("title", "name")),
        "url": url,
        "tags": first_string_list(record, ("tags", "hashtags")),
        "note": first_string(record, ("notes", "body", "note")),
      }
    )

  os.makedirs(args.output_dir, exist_ok=True)
  output_path = os.path.join(args.output_dir, "reminders-links.yaml")
  with open(output_path, "w", encoding="utf-8") as f:
    f.write(make_yaml(links))

  print(f"Exported {len(links)} links with {used_rem} to {output_path}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
