#!/usr/bin/python3
import json
import os
import shutil
import struct
import subprocess
import sys


LIST_NAME = "链接"
REM_BINARY = "/opt/homebrew/bin/rem"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
LOCAL_REM_BINARY = os.path.abspath(os.path.join(SCRIPT_DIR, "..", "bin", "rem"))


def read_message():
  raw_length = sys.stdin.buffer.read(4)
  if len(raw_length) == 0:
    return None
  if len(raw_length) != 4:
    raise ValueError("Invalid native message length header")
  message_length = struct.unpack("<I", raw_length)[0]
  if message_length > 1024 * 1024:
    raise ValueError("Native message is too large")
  data = sys.stdin.buffer.read(message_length)
  return json.loads(data.decode("utf-8"))


def write_message(message):
  encoded = json.dumps(message, ensure_ascii=False).encode("utf-8")
  sys.stdout.buffer.write(struct.pack("<I", len(encoded)))
  sys.stdout.buffer.write(encoded)
  sys.stdout.buffer.flush()


def normalize_tags(tags):
  if not isinstance(tags, list):
    return []
  result = []
  for tag in tags:
    value = str(tag).strip().lstrip("#")
    if value and value not in result:
      result.append(value)
  return result


def get_rem_binary():
  if os.path.isfile(LOCAL_REM_BINARY) and os.access(LOCAL_REM_BINARY, os.X_OK):
    return LOCAL_REM_BINARY
  rem = REM_BINARY if shutil.which(REM_BINARY) else shutil.which("rem")
  if not rem:
    raise FileNotFoundError("rem CLI 未安装，无法写入原生链接卡片和标签")
  return rem


def collect_tags(value, result):
  if isinstance(value, dict):
    for key, child in value.items():
      if key in ("tags", "hashtags"):
        collect_tags(child, result)
      elif isinstance(child, (dict, list)):
        collect_tags(child, result)
    return

  if isinstance(value, list):
    for item in value:
      collect_tags(item, result)
    return

  if isinstance(value, str):
    tag = value.strip().lstrip("#")
    if tag:
      result.add(tag)


def list_existing_tags(filter_text):
  rem = get_rem_binary()
  result = subprocess.run(
    [rem, "list", "--list", LIST_NAME, "--output", "json"],
    check=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
  )

  tags = set()
  try:
    reminders = json.loads(result.stdout)
  except json.JSONDecodeError:
    reminders = []
  collect_tags(reminders, tags)

  if filter_text:
    tags = {tag for tag in tags if filter_text in tag}
  return sorted(tags, key=str.casefold)


def save_with_rem(title, url, note, tags):
  rem = get_rem_binary()

  command = [
    rem,
    "add",
    title,
    "--list",
    LIST_NAME,
    "--url",
    url,
    "--output",
    "json",
  ]
  if note:
    command.extend(["--notes", note])
  if tags:
    command.extend(["--tags", ",".join(tags)])

  subprocess.run(
    command,
    check=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
  )


def save_to_reminders(title, url, note, tags):
  try:
    save_with_rem(title, url, note, tags)
    return
  except FileNotFoundError:
    pass

  script = """
on run argv
  set listName to item 1 of argv
  set reminderTitle to item 2 of argv
  set reminderBody to item 3 of argv

  tell application "Reminders"
    if not (exists list listName) then
      make new list with properties {name:listName}
    end if
    tell list listName
      make new reminder with properties {name:reminderTitle, body:reminderBody}
    end tell
  end tell
end run
"""
  subprocess.run(
    ["osascript", "-e", script, LIST_NAME, title, note],
    check=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
  )


def handle(message):
  if message.get("action") == "list_tags":
    filter_text = str(message.get("filter") or "链接").strip()
    return {"ok": True, "tags": list_existing_tags(filter_text)}

  if message.get("action") != "save_link":
    raise ValueError("Unknown action")

  title = str(message.get("title") or "").strip()
  url = str(message.get("url") or "").strip()
  note = str(message.get("note") or "").strip()
  tags = normalize_tags(message.get("tags"))

  if not url:
    raise ValueError("Missing URL")
  if not title:
    title = url

  save_to_reminders(title, url, note, tags)
  return {"ok": True}


def main():
  try:
    message = read_message()
    if message is None:
      return
    write_message(handle(message))
  except subprocess.CalledProcessError as error:
    detail = (error.stderr or error.stdout or str(error)).strip()
    if "access denied" in detail.lower() or "reminders access denied" in detail.lower():
      detail = detail + "。请在终端运行 `rem lists`，按系统提示允许访问提醒事项后再试。"
    write_message({"ok": False, "error": f"Reminders 写入失败：{detail}"})
  except Exception as error:
    write_message({"ok": False, "error": str(error)})


if __name__ == "__main__":
  main()
