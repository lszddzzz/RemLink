# Remlink

[English README](readme.md)

Remlink 是一个 macOS 工具 App、Native helper 和 Chromium 系浏览器扩展，用来把当前网页保存到 Apple 提醒事项。

浏览器扩展会把当前页面保存到名为 `链接` 的提醒事项列表中，并支持可编辑标题、提醒事项 URL、备注和井号标签。macOS App 负责让扩展可以持久化和复刻：它会把扩展运行文件同步到你选择的持久化文件夹，安装 Native Messaging 配置，内置用于 YAML 导入导出的 `rem` 依赖，并提供 `链接` 列表的 YAML 导入和导出。

## 仓库结构

- `Sources/Remlink/App.swift`: SwiftUI 管理 App
- `Sources/RemlinkHelper`: 浏览器按需启动的 Native Messaging helper
- `Sources/Remlink/Resources/extension`: Chromium 扩展
- `Sources/Remlink/Resources/native`: 保留作开发 fallback 的旧 Python host
- `Sources/Remlink/Resources/scripts`: YAML 导出脚本，也供 LaunchAgent 使用
- `Sources/Remlink/Resources/bin/rem`: 内置 `rem` CLI 依赖
- `Sources/Remlink/Resources/app`: App 图标资源
- `build_app.sh`: 构建 `Remlink.app`
- `install_native_host.sh`: 开发时从源码目录安装 Native Messaging host 的辅助脚本

## 构建

```bash
cd /Users/lszddz/Code/Code通用/浏览器插件/reminders-link-saver-manager
./build_app.sh
```

构建后的 App 位于：

```text
/Users/lszddz/Code/Code通用/浏览器插件/reminders-link-saver-manager/.build/Remlink.app
```

## 初次设置

1. 打开 `Remlink.app`。
2. 选择一个持久化文件夹。
3. 点击 `授权提醒事项`。
4. 点击 `安装依赖`。
5. 点击 `同步插件到持久化目录`。
6. 打开浏览器扩展管理页，加载复制后的扩展文件夹：

```text
<你的持久化文件夹>/extension
```

开发时也可以直接加载仓库中的扩展目录：

```text
/Users/lszddz/Code/Code通用/浏览器插件/reminders-link-saver-manager/Sources/Remlink/Resources/extension
```

扩展默认快捷键是：

```text
Alt+Shift+L
```

可以在这里修改：

```text
chrome://extensions/shortcuts
```

## YAML 导出和导入

`导出链接 YAML` 会导出 `链接` 列表中所有带 URL 的提醒事项。

每条记录包含：

- `title`: 链接标题
- `url`: URL
- `tags`: 提醒事项原生标签
- `note`: 备注正文

示例：

```yaml
links:
  - title: "Example"
    url: "https://example.com/"
    tags:
      - "链接-资料"
    note: |-
      Note text
```

`从 YAML 导入` 会按照同一格式追加创建提醒事项。当前不会自动去重。

## 每日自动导出

`安装每日自动导出` 会安装用户级 LaunchAgent：

```text
~/Library/LaunchAgents/com.landlord.remlink.daily-export.plist
```

它每天 11:00 运行，并覆盖更新：

```text
<你的持久化文件夹>/exports/reminders-links.yaml
```

日志写入：

```text
<你的持久化文件夹>/logs/daily-export.out.log
<你的持久化文件夹>/logs/daily-export.err.log
```

Remlink 启动时会检查这个 LaunchAgent 是否存在，以及是否仍指向当前选择的持久化文件夹。如果缺失或过期，Remlink 会自动重新安装。

## Native Messaging

扩展使用的 native host 名称是：

```text
com.landlord.remlink
```

host 路径会指向签名后的 helper：

```text
/Applications/Remlink.app/Contents/Helpers/RemlinkHelper.app/Contents/MacOS/RemlinkHelper
```

管理 App 会为 Chrome、Chromium、Brave、Edge、Arc 和 Helium 写入 Native Messaging manifest。开发时也可以从仓库中运行：

```bash
./install_native_host.sh
```

## 提醒事项权限

浏览器扩展通过 `RemlinkHelper` 写入提醒事项。YAML 导入和导出仍使用内置或 Homebrew 安装的 `rem` CLI。如果浏览器保存时报提醒事项权限错误，请在 App 中点击 `授权提醒事项`，并允许 `RemlinkHelper` 访问提醒事项；如果导入或导出失败，也需要允许 `rem` 访问提醒事项。

如果 macOS 没有弹出授权窗口，请检查：

```text
系统设置 → 隐私与安全性 → 提醒事项
```

## 发布

GitHub Actions 会在推送 `v*` 标签时构建 App，并创建 GitHub Release。也可以在 GitHub Actions 页面手动运行 release workflow。
