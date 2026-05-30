# Remlink

[中文说明](README.zh-CN.md)

Remlink is a macOS utility and Chromium extension for saving web links into Apple Reminders.

The extension saves the current page into the Reminders list named `链接`, with an editable title, native Reminders URL card, native tags, and notes. The macOS app keeps the extension portable: it copies the extension runtime into a chosen persistent folder, installs Native Messaging manifests, carries the `rem` dependency, and can export/import the `链接` list as YAML.

## Repository Layout

- `Sources/Remlink/App.swift`: SwiftUI manager app
- `Sources/Remlink/Resources/extension`: Chromium extension
- `Sources/Remlink/Resources/native`: Native Messaging host
- `Sources/Remlink/Resources/scripts`: YAML export helper used by LaunchAgent
- `Sources/Remlink/Resources/bin/rem`: bundled `rem` CLI dependency
- `Sources/Remlink/Resources/app`: app icon resources
- `build_app.sh`: builds `Remlink.app`
- `install_native_host.sh`: developer-only helper for installing the Native Messaging host from this repository

## Build

```bash
cd /Users/lszddz/Code/Code通用/浏览器插件/reminders-link-saver-manager
./build_app.sh
```

The built app is:

```text
/Users/lszddz/Code/Code通用/浏览器插件/reminders-link-saver-manager/.build/Remlink.app
```

## Setup Flow

1. Open `Remlink.app`.
2. Choose a persistent folder.
3. Click `授权提醒事项`.
4. Click `安装依赖`.
5. Click `同步插件到持久化目录`.
6. Open the browser extension page and load the copied extension folder:

```text
<your persistent folder>/extension
```

For development, you can also load the extension directly from the repository:

```text
/Users/lszddz/Code/Code通用/浏览器插件/reminders-link-saver-manager/Sources/Remlink/Resources/extension
```

The extension shortcut defaults to:

```text
Alt+Shift+L
```

It can be changed from:

```text
chrome://extensions/shortcuts
```

## YAML Export And Import

`导出链接 YAML` exports every reminder in the `链接` list that has a URL.

Each record contains:

- `title`: link title
- `url`: URL
- `tags`: native Reminders tags
- `note`: notes/body text

Example:

```yaml
links:
  - title: "Example"
    url: "https://example.com/"
    tags:
      - "链接-资料"
    note: |-
      Note text
```

`从 YAML 导入` appends reminders from the same format. It does not deduplicate existing reminders.

## Daily Export

`安装每日自动导出` installs a user LaunchAgent:

```text
~/Library/LaunchAgents/com.landlord.remlink.daily-export.plist
```

It runs every day at 11:00 and overwrites:

```text
<your persistent folder>/exports/reminders-links.yaml
```

Logs are written to:

```text
<your persistent folder>/logs/daily-export.out.log
<your persistent folder>/logs/daily-export.err.log
```

When Remlink opens, it checks whether this LaunchAgent exists and still points to the selected persistent folder. If it is missing or stale, Remlink reinstalls it automatically.

## Native Messaging

The extension talks to the native host named:

```text
com.landlord.remlink
```

The manager app writes manifests for Chrome, Chromium, Brave, Edge, and Arc. The developer helper can do the same from the repository:

```bash
./install_native_host.sh
```

## Reminders Permission

Remlink uses the bundled or Homebrew `rem` CLI to access Reminders. If export/import fails with a Reminders permission error, click `授权提醒事项` in the app and allow Reminders access in macOS.

If macOS does not show a prompt, check:

```text
系统设置 → 隐私与安全性 → 提醒事项
```

## Release

GitHub Actions builds the app and creates a GitHub Release when a `v*` tag is pushed. The release workflow can also be started manually from the GitHub Actions page.
