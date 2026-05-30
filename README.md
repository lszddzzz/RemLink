# 提醒事项链接收藏器管理器

这是一个极简 SwiftUI macOS App，用来在新电脑上复刻 Chromium 扩展的完整运行环境。

它会做三件事：

- 选择并记住一个持久化目录
- 把浏览器扩展、Native Messaging host 和 `rem` 依赖复制到该目录
- 写入 Chrome、Chromium、Brave、Edge、Arc 的 Native Messaging 配置
- 将提醒事项“链接”列表导出为 YAML，并可从 YAML 导入

## 构建 App

```bash
cd /Users/lszddz/Code/Code通用/浏览器插件/reminders-link-saver-manager
./build_app.sh
```

构建完成后会得到：

```text
/Users/lszddz/Code/Code通用/浏览器插件/reminders-link-saver-manager/.build/RemindersLinkSaverManager.app
```

## 使用流程

1. 打开 App。
2. 选择一个文件夹作为持久化目录。
3. 点击“安装依赖”。
4. 点击“同步插件到持久化目录”。
5. 打开浏览器扩展页，加载持久化目录里的 `extension` 文件夹。

“授权提醒事项”按钮放在前面。导出、导入和自动导出都依赖这个权限；如果系统设置里已经授权了 Homebrew 的 `rem`，App 会优先复用 `/opt/homebrew/bin/rem`。

加载扩展的目录示例：

```text
你选择的目录/extension
```

首次使用时，如果 Reminders 权限报错，在普通终端执行：

```bash
你选择的目录/bin/rem lists
```

然后允许访问提醒事项。

也可以在 App 中点击“授权提醒事项”，它会运行同等的权限检查并触发 macOS 授权。

## YAML 导入导出

点击“导出链接 YAML”会读取提醒事项的“链接”列表，并导出所有带 URL 的事项。每条记录包含：

- `title`：链接标题
- `url`：URL
- `tags`：原生标签
- `note`：备注

导出格式示例：

```yaml
links:
  - title: "示例页面"
    url: "https://example.com/"
    tags:
      - "链接-资料"
    note: |-
      这里是备注
```

点击“从 YAML 导入”会按同一格式重建提醒事项。当前导入策略是追加创建，不会自动去重。

## 每日自动导出

点击“安装每日自动导出”后，App 会安装一个当前用户的 LaunchAgent：

```text
~/Library/LaunchAgents/com.landlord.reminders-link-saver.daily-export.plist
```

它每天 11:00 自动导出“链接”列表，固定覆盖持久化目录中的同一个文件：

```text
exports/reminders-links.yaml
```

日志写到：

```text
logs/daily-export.out.log
logs/daily-export.err.log
```

App 每次打开时会检查这个 LaunchAgent 是否还存在、是否仍指向当前持久化目录；如果缺失或指向旧目录，会自动重新安装。
