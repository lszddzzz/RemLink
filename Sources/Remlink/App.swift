import AppKit
import Darwin
import SwiftUI
import UniformTypeIdentifiers

private enum Constants {
  static let hostName = "com.landlord.remlink"
  static let extensionID = "gomigjglhhobgbplnnofkhooolekeohd"
  static let extensionPage = "chrome://extensions/"
  static let shortcutsPage = "chrome://extensions/shortcuts"
  static let listName = "链接"
  static let dailyExportAgentID = "com.landlord.remlink.daily-export"
}

@main
struct RemlinkApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
        .frame(width: 520, height: 540)
    }
    .windowStyle(.hiddenTitleBar)
  }
}

struct ContentView: View {
  @AppStorage("installDirectory") private var installDirectory = ""
  @AppStorage("didCompleteInitialSetup") private var didCompleteInitialSetup = false
  @State private var status = "请选择一个持久化目录。"
  @State private var isWorking = false

  private var selectedURL: URL? {
    installDirectory.isEmpty ? nil : URL(fileURLWithPath: installDirectory)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Remlink")
          .font(.system(size: 22, weight: .semibold))
        Text("把浏览器插件、Native host 和依赖复制到一个可迁移目录。")
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
      }

      Divider()

      VStack(alignment: .leading, spacing: 8) {
        Text("持久化目录")
          .font(.system(size: 13, weight: .semibold))
        Text(installDirectory.isEmpty ? "未选择" : installDirectory)
          .font(.system(size: 12, design: .monospaced))
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .textSelection(.enabled)

        HStack {
          Button("选择文件夹") {
            chooseFolder()
          }
          Button("打开文件夹") {
            if let selectedURL {
              NSWorkspace.shared.open(selectedURL)
            }
          }
          .disabled(selectedURL == nil)
        }
      }

      HStack(spacing: 10) {
        Button("授权提醒事项") {
          runTask("授权提醒事项") {
            try authorizeReminders()
          }
        }
        .disabled(isWorking)

        Button("安装依赖") {
          runTask("安装依赖") {
            try installDependencies()
            return nil
          }
        }
        .disabled(selectedURL == nil || isWorking)
      }

      HStack(spacing: 10) {
        Button("同步插件到持久化目录") {
          runTask("同步插件") {
            try installPlugin()
            didCompleteInitialSetup = true
            return nil
          }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(selectedURL == nil || isWorking)

        Button("安装每日自动导出") {
          runTask("安装每日自动导出") {
            try installDailyExportAgent()
          }
        }
        .disabled(selectedURL == nil || isWorking)
      }

      HStack(spacing: 10) {
        Button("打开扩展页") {
          openBrowserInternalPage(Constants.extensionPage)
        }
        Button("打开快捷键页") {
          openBrowserInternalPage(Constants.shortcutsPage)
        }
      }

      HStack(spacing: 10) {
        Button("导出链接 YAML") {
          runTask("导出 YAML") {
            try exportLinksYAML()
          }
        }
        .disabled(isWorking)

        Button("从 YAML 导入") {
          runTask("导入 YAML") {
            try importLinksYAML()
          }
        }
        .disabled(isWorking)
      }

      Spacer()

      VStack(alignment: .leading, spacing: 8) {
        Text(didCompleteInitialSetup ? "已记录你的选择" : "首次设置未完成")
          .font(.system(size: 13, weight: .semibold))
        Text(status)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .lineLimit(4)
          .textSelection(.enabled)
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(nsColor: .controlBackgroundColor))
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .padding(22)
    .onAppear {
      ensureDailyExportAgentIfNeeded()
    }
  }

  private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.prompt = "选择"

    if panel.runModal() == .OK, let url = panel.url {
      installDirectory = url.path
      status = "已选择：\(url.path)"
      ensureDailyExportAgentIfNeeded()
    }
  }

  private func runTask(_ label: String, _ work: @escaping () throws -> String?) {
    guard !isWorking else { return }
    isWorking = true
    status = "\(label)中..."

    do {
      status = try work() ?? "\(label)完成。"
    } catch {
      status = "\(label)失败：\(error.localizedDescription)"
    }
    isWorking = false
  }

  private func installDependencies() throws {
    let installURL = try requireInstallDirectory()
    let resourceURL = try bundledResourcesURL()
    let bundledRem = resourceURL.appendingPathComponent("bin/rem")
    let targetBin = installURL.appendingPathComponent("bin", isDirectory: true)
    let targetRem = targetBin.appendingPathComponent("rem")

    try FileManager.default.createDirectory(at: targetBin, withIntermediateDirectories: true)
    try replaceItem(at: targetRem, with: bundledRem)
    try chmodExecutable(targetRem)
  }

  private func installPlugin() throws {
    let installURL = try requireInstallDirectory()
    let resourceURL = try bundledResourcesURL()

    try installDependencies()
    try replaceDirectory(
      at: installURL.appendingPathComponent("extension", isDirectory: true),
      with: resourceURL.appendingPathComponent("extension", isDirectory: true)
    )
    try replaceDirectory(
      at: installURL.appendingPathComponent("native", isDirectory: true),
      with: resourceURL.appendingPathComponent("native", isDirectory: true)
    )
    try replaceDirectory(
      at: installURL.appendingPathComponent("scripts", isDirectory: true),
      with: resourceURL.appendingPathComponent("scripts", isDirectory: true)
    )
    try chmodExecutable(installURL.appendingPathComponent("native/reminders_host.py"))
    try chmodExecutable(installURL.appendingPathComponent("scripts/export_links_yaml.py"))
    try writeNativeMessagingManifests(hostPath: helperHostURL().path)
  }

  private func requireInstallDirectory() throws -> URL {
    guard let selectedURL else {
      throw ManagerError("请先选择文件夹。")
    }
    try FileManager.default.createDirectory(at: selectedURL, withIntermediateDirectories: true)
    return selectedURL
  }

  private func bundledResourcesURL() throws -> URL {
    let mainResourceURL = Bundle.main.resourceURL
    let candidates = [
      Bundle.module.resourceURL,
      Bundle.module.resourceURL?.appendingPathComponent("Resources", isDirectory: true),
      mainResourceURL?.appendingPathComponent("Resources", isDirectory: true),
      mainResourceURL?.appendingPathComponent("Remlink_Remlink.bundle/Resources", isDirectory: true)
    ].compactMap { $0 }

    for candidate in candidates where hasBundledPayload(at: candidate) {
      return candidate
    }
    throw ManagerError("找不到 App 内置资源。")
  }

  private func hasBundledPayload(at url: URL) -> Bool {
    let extensionManifest = url.appendingPathComponent("extension/manifest.json").path
    let nativeHost = url.appendingPathComponent("native/reminders_host.py").path
    let exportScript = url.appendingPathComponent("scripts/export_links_yaml.py").path
    let rem = url.appendingPathComponent("bin/rem").path
    return FileManager.default.fileExists(atPath: extensionManifest)
      && FileManager.default.fileExists(atPath: nativeHost)
      && FileManager.default.fileExists(atPath: exportScript)
      && FileManager.default.fileExists(atPath: rem)
  }

  private func openBrowserInternalPage(_ urlString: String) {
    guard let httpsURL = URL(string: "https://www.apple.com/") else {
      copyToPasteboard(urlString)
      return
    }

    if let browserURL = NSWorkspace.shared.urlForApplication(toOpen: httpsURL) {
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true
      NSWorkspace.shared.open([URL(string: urlString)!], withApplicationAt: browserURL, configuration: configuration) { _, error in
        DispatchQueue.main.async {
          if let error {
            copyToPasteboard(urlString)
            status = "无法直接打开该内部页面：\(error.localizedDescription)。已把链接复制到剪贴板，请在默认浏览器地址栏粘贴打开。"
          } else {
            status = "已在默认浏览器打开：\(urlString)"
          }
        }
      }
      return
    }

    if NSWorkspace.shared.open(httpsURL) {
      copyToPasteboard(urlString)
      status = "已打开默认浏览器，并把 \(urlString) 复制到剪贴板。请在地址栏粘贴打开。"
    } else {
      copyToPasteboard(urlString)
      status = "未能打开默认浏览器。已把 \(urlString) 复制到剪贴板。"
    }
  }

  private func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  private func replaceDirectory(at destination: URL, with source: URL) throws {
    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.copyItem(at: source, to: destination)
  }

  private func replaceItem(at destination: URL, with source: URL) throws {
    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.copyItem(at: source, to: destination)
  }

  private func chmodExecutable(_ url: URL) throws {
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
  }

  private func writeNativeMessagingManifests(hostPath: String) throws {
    let manifest: [String: Any] = [
      "name": Constants.hostName,
      "description": "Save Chromium links to Reminders with Remlink",
      "path": hostPath,
      "type": "stdio",
      "allowed_origins": ["chrome-extension://\(Constants.extensionID)/"]
    ]

    let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    let home = FileManager.default.homeDirectoryForCurrentUser
    let directories = [
      "Library/Application Support/Google/Chrome/NativeMessagingHosts",
      "Library/Application Support/Chromium/NativeMessagingHosts",
      "Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts",
      "Library/Application Support/Microsoft Edge/NativeMessagingHosts",
      "Library/Application Support/Arc/User Data/NativeMessagingHosts",
      "Library/Application Support/net.imput.helium/NativeMessagingHosts"
    ]

    for directory in directories {
      let targetDirectory = home.appendingPathComponent(directory, isDirectory: true)
      try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
      let target = targetDirectory.appendingPathComponent("\(Constants.hostName).json")
      try data.write(to: target, options: .atomic)
    }
  }

  private func helperHostURL() throws -> URL {
    let candidates = [
      Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/RemlinkHelper.app/Contents/MacOS/RemlinkHelper"),
      Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/RemlinkHelper"),
      Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("RemlinkHelper")
    ].compactMap { $0 }

    for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
      return candidate
    }
    throw ManagerError("找不到 RemlinkHelper。请重新构建并从 /Applications/Remlink.app 启动。")
  }

  private func exportLinksYAML() throws -> String {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.yaml]
    panel.nameFieldStringValue = "reminders-links.yaml"
    panel.canCreateDirectories = true

    guard panel.runModal() == .OK, let targetURL = panel.url else {
      throw ManagerError("已取消导出。")
    }

    let links = try fetchReminderLinks()
    let yaml = makeYAML(links)
    try yaml.write(to: targetURL, atomically: true, encoding: .utf8)
    return "已导出 \(links.count) 条链接到：\(targetURL.path)"
  }

  private func importLinksYAML() throws -> String {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.yaml, .text]
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false

    guard panel.runModal() == .OK, let sourceURL = panel.url else {
      throw ManagerError("已取消导入。")
    }

    let yaml = try String(contentsOf: sourceURL, encoding: .utf8)
    let links = try parseLinksYAML(yaml)

    for link in links {
      var arguments = [
        "add",
        link.title.isEmpty ? link.url : link.title,
        "--list",
        Constants.listName,
        "--url",
        link.url,
        "--output",
        "json"
      ]
      if !link.note.isEmpty {
        arguments += ["--notes", link.note]
      }
      if !link.tags.isEmpty {
        arguments += ["--tags", link.tags.joined(separator: ",")]
      }
      _ = try runRem(arguments: arguments)
    }

    return "已从 YAML 导入 \(links.count) 条链接。"
  }

  private func installDailyExportAgent() throws -> String {
    try writeDailyExportAgent()
    let outputURL = try requireInstallDirectory().appendingPathComponent("exports/reminders-links.yaml")
    return "已安装每日 11:00 自动导出。YAML 将持续更新：\(outputURL.path)"
  }

  private func ensureDailyExportAgentIfNeeded() {
    guard !installDirectory.isEmpty, !isWorking else {
      return
    }

    do {
      if try shouldInstallDailyExportAgent() {
        try writeDailyExportAgent()
        status = "已检查并恢复每日 11:00 自动导出。"
      }
    } catch {
      status = "检查每日自动导出失败：\(error.localizedDescription)"
    }
  }

  private func shouldInstallDailyExportAgent() throws -> Bool {
    let plistURL = dailyExportPlistURL()
    guard FileManager.default.fileExists(atPath: plistURL.path) else {
      return true
    }

    let data = try Data(contentsOf: plistURL)
    guard
      let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
      let arguments = plist["ProgramArguments"] as? [String]
    else {
      return true
    }

    let installURL = try requireInstallDirectory()
    let exportScript = installURL.appendingPathComponent("scripts/export_links_yaml.py").path
    let outputURL = installURL.appendingPathComponent("exports").path
    return !arguments.contains(exportScript) || !arguments.contains(outputURL)
  }

  private func writeDailyExportAgent() throws {
    let installURL = try requireInstallDirectory()
    try installPlugin()

    let scriptsURL = installURL.appendingPathComponent("scripts", isDirectory: true)
    let exportScript = scriptsURL.appendingPathComponent("export_links_yaml.py")
    let outputURL = installURL.appendingPathComponent("exports", isDirectory: true)
    let logsURL = installURL.appendingPathComponent("logs", isDirectory: true)
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)

    let homebrewRem = URL(fileURLWithPath: "/opt/homebrew/bin/rem")
    let installedRem = installURL.appendingPathComponent("bin/rem")
    let plistURL = dailyExportPlistURL()

    let plist: [String: Any] = [
      "Label": Constants.dailyExportAgentID,
      "ProgramArguments": [
        "/usr/bin/python3",
        exportScript.path,
        "--list",
        Constants.listName,
        "--output-dir",
        outputURL.path,
        "--rem",
        homebrewRem.path,
        "--rem",
        installedRem.path
      ],
      "StartCalendarInterval": [
        "Hour": 11,
        "Minute": 0
      ],
      "StandardOutPath": logsURL.appendingPathComponent("daily-export.out.log").path,
      "StandardErrorPath": logsURL.appendingPathComponent("daily-export.err.log").path
    ]

    let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try plistData.write(to: plistURL, options: .atomic)

    let domain = "gui/\(getuid())"
    _ = try? runSystemProcess("/bin/launchctl", arguments: ["bootout", domain, plistURL.path])
    _ = try runSystemProcess("/bin/launchctl", arguments: ["bootstrap", domain, plistURL.path])
  }

  private func dailyExportPlistURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents/\(Constants.dailyExportAgentID).plist")
  }

  private func authorizeReminders() throws -> String {
    _ = try runProcess(try helperHostURL(), arguments: ["--authorize"])
    return "RemlinkHelper 提醒事项授权可用。浏览器插件现在会通过 RemlinkHelper 写入提醒事项。"
  }

  private func fetchReminderLinks() throws -> [ReminderLink] {
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("reminders-links-\(UUID().uuidString).json")
    defer {
      try? FileManager.default.removeItem(at: tempURL)
    }

    _ = try runRem(arguments: [
      "export",
      "--list",
      Constants.listName,
      "--format",
      "json",
      "--output-file",
      tempURL.path
    ])

    let data = try Data(contentsOf: tempURL)
    let object = try JSONSerialization.jsonObject(with: data)
    let records = extractReminderRecords(from: object)

    return records.compactMap { record in
      let title = firstString(record, keys: ["title", "name"])
      let url = firstString(record, keys: ["url", "URL", "link"])
      let note = firstString(record, keys: ["notes", "body", "note"])
      let tags = firstStringArray(record, keys: ["tags", "hashtags"])
      guard !url.isEmpty else { return nil }
      return ReminderLink(title: title, url: url, tags: tags, note: note)
    }
  }

  private func availableRemBinaries() -> [URL] {
    var candidates: [URL] = []

    let homebrewRem = URL(fileURLWithPath: "/opt/homebrew/bin/rem")
    if FileManager.default.isExecutableFile(atPath: homebrewRem.path) {
      candidates.append(homebrewRem)
    }

    if let selectedURL {
      let installedRem = selectedURL.appendingPathComponent("bin/rem")
      if FileManager.default.isExecutableFile(atPath: installedRem.path) {
        candidates.append(installedRem)
      }
    }

    if let bundledRem = try? bundledResourcesURL().appendingPathComponent("bin/rem"),
       FileManager.default.isExecutableFile(atPath: bundledRem.path) {
      candidates.append(bundledRem)
    }

    var seen = Set<String>()
    return candidates.filter { candidate in
      if seen.contains(candidate.path) {
        return false
      }
      seen.insert(candidate.path)
      return true
    }
  }

  private func runRem(arguments: [String]) throws -> (output: String, executable: URL) {
    let candidates = availableRemBinaries()
    guard !candidates.isEmpty else {
      throw ManagerError("找不到可执行的 rem。请先点击“安装依赖”。")
    }

    var errors: [String] = []
    for candidate in candidates {
      do {
        let output = try runProcess(candidate, arguments: arguments)
        return (output, candidate)
      } catch {
        let message = error.localizedDescription
        errors.append("\(candidate.path)：\(message)")
        if !isRemindersAccessDenied(message) {
          throw error
        }
      }
    }

    throw ManagerError(
      "所有 rem 都被提醒事项权限拒绝。请在 系统设置 → 隐私与安全性 → 提醒事项 中确认这些路径对应的 rem 已允许：\n"
        + errors.joined(separator: "\n")
    )
  }

  private func runProcess(_ executable: URL, arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    guard process.terminationStatus == 0 else {
      let detail = error.isEmpty ? output : error
      throw ManagerError(friendlyProcessError(detail))
    }
    return output
  }

  private func runSystemProcess(_ executablePath: String, arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = arguments

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    guard process.terminationStatus == 0 else {
      throw ManagerError((error.isEmpty ? output : error).trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return output
  }

  private func friendlyProcessError(_ detail: String) -> String {
    let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
    let lowercased = trimmed.lowercased()
    if lowercased.contains("reminders access denied") || lowercased.contains("failed to initialize reminders access") {
      return "提醒事项访问被拒绝。请点击“授权提醒事项”，并在 macOS 弹窗中允许访问；如果没有弹窗，请到 系统设置 → 隐私与安全性 → 提醒事项 中允许本 App 或 rem。"
    }
    return trimmed
  }

  private func isRemindersAccessDenied(_ message: String) -> Bool {
    let lowercased = message.lowercased()
    return lowercased.contains("提醒事项访问被拒绝")
      || lowercased.contains("reminders access denied")
      || lowercased.contains("failed to initialize reminders access")
  }
}

struct ManagerError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? {
    message
  }
}

struct ReminderLink {
  var title: String
  var url: String
  var tags: [String]
  var note: String
}

private func extractReminderRecords(from object: Any) -> [[String: Any]] {
  if let array = object as? [[String: Any]] {
    return array
  }
  if let dictionary = object as? [String: Any] {
    for key in ["reminders", "items", "data"] {
      if let records = dictionary[key] {
        let extracted = extractReminderRecords(from: records)
        if !extracted.isEmpty {
          return extracted
        }
      }
    }
  }
  return []
}

private func firstString(_ dictionary: [String: Any], keys: [String]) -> String {
  for key in keys {
    if let value = dictionary[key] as? String {
      return value
    }
    if let value = dictionary[key] {
      return String(describing: value)
    }
  }
  return ""
}

private func firstStringArray(_ dictionary: [String: Any], keys: [String]) -> [String] {
  for key in keys {
    if let values = dictionary[key] as? [String] {
      return values
    }
    if let values = dictionary[key] as? [Any] {
      return values.map { String(describing: $0) }.filter { !$0.isEmpty }
    }
  }
  return []
}

private func makeYAML(_ links: [ReminderLink]) -> String {
  var lines = ["links:"]
  for link in links {
    lines.append("  - title: \(yamlQuote(link.title))")
    lines.append("    url: \(yamlQuote(link.url))")
    lines.append("    tags:")
    if link.tags.isEmpty {
      lines.append("      []")
    } else {
      for tag in link.tags {
        lines.append("      - \(yamlQuote(tag))")
      }
    }
    if link.note.isEmpty {
      lines.append("    note: \"\"")
    } else {
      lines.append("    note: |-")
      for noteLine in link.note.components(separatedBy: .newlines) {
        lines.append("      \(noteLine)")
      }
    }
  }
  return lines.joined(separator: "\n") + "\n"
}

private func yamlQuote(_ value: String) -> String {
  let escaped = value
    .replacingOccurrences(of: "\\", with: "\\\\")
    .replacingOccurrences(of: "\"", with: "\\\"")
  return "\"\(escaped)\""
}

private func yamlUnquote(_ value: String) -> String {
  var text = value.trimmingCharacters(in: .whitespaces)
  if text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 {
    text.removeFirst()
    text.removeLast()
  }

  var result = ""
  var isEscaping = false
  for character in text {
    if isEscaping {
      result.append(character)
      isEscaping = false
    } else if character == "\\" {
      isEscaping = true
    } else {
      result.append(character)
    }
  }
  return result
}

private func parseLinksYAML(_ yaml: String) throws -> [ReminderLink] {
  let lines = yaml.components(separatedBy: .newlines)
  var links: [ReminderLink] = []
  var current: ReminderLink?
  var index = 0

  func finishCurrent() {
    if let item = current, !item.url.isEmpty {
      links.append(item)
    }
  }

  while index < lines.count {
    let line = lines[index]
    if line.hasPrefix("  - title:") {
      finishCurrent()
      current = ReminderLink(
        title: yamlUnquote(String(line.dropFirst("  - title:".count))),
        url: "",
        tags: [],
        note: ""
      )
    } else if line.hasPrefix("    url:") {
      current?.url = yamlUnquote(String(line.dropFirst("    url:".count)))
    } else if line == "    tags:" {
      index += 1
      while index < lines.count {
        let tagLine = lines[index]
        if tagLine.hasPrefix("      - ") {
          current?.tags.append(yamlUnquote(String(tagLine.dropFirst("      - ".count))))
          index += 1
          continue
        }
        if tagLine.trimmingCharacters(in: .whitespaces) == "[]" {
          index += 1
          continue
        }
        index -= 1
        break
      }
    } else if line == "    note: |-" {
      var noteLines: [String] = []
      index += 1
      while index < lines.count {
        let noteLine = lines[index]
        if noteLine.hasPrefix("      ") {
          noteLines.append(String(noteLine.dropFirst(6)))
          index += 1
          continue
        }
        index -= 1
        break
      }
      current?.note = noteLines.joined(separator: "\n")
    } else if line.hasPrefix("    note:") {
      current?.note = yamlUnquote(String(line.dropFirst("    note:".count)))
    }
    index += 1
  }

  finishCurrent()
  guard !links.isEmpty else {
    throw ManagerError("YAML 中没有可导入的链接。")
  }
  return links
}
