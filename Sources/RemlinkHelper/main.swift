import EventKit
import Foundation

private let listName = "链接"
private let maxMessageSize = 1024 * 1024

struct NativeRequest: Decodable {
  var action: String?
  var title: String?
  var url: String?
  var note: String?
  var tags: [String]?
  var filter: String?
}

struct NativeResponse: Encodable {
  var ok: Bool
  var tags: [String]?
  var error: String?
}

enum HelperError: LocalizedError {
  case invalidLengthHeader
  case messageTooLarge
  case invalidRequest
  case remindersAccessDenied
  case missingURL
  case listUnavailable
  case remUnavailable
  case remFailed(String)

  var errorDescription: String? {
    switch self {
    case .invalidLengthHeader:
      return "Invalid native message length header"
    case .messageTooLarge:
      return "Native message is too large"
    case .invalidRequest:
      return "Unknown action"
    case .remindersAccessDenied:
      return "提醒事项访问被拒绝。请在 Remlink 中点击“授权提醒事项”，并在 macOS 弹窗中允许访问。"
    case .missingURL:
      return "Missing URL"
    case .listUnavailable:
      return "无法创建或找到“\(listName)”提醒事项列表。"
    case .remUnavailable:
      return "找不到 Remlink 内置 rem。请重新构建并安装 /Applications/Remlink.app。"
    case .remFailed(let detail):
      if isRemindersAccessDenied(detail) {
        return "rem 提醒事项访问被拒绝。请在 Remlink 中点击“授权提醒事项”，并在 macOS 弹窗中允许访问。"
      }
      return detail
    }
  }
}

@main
struct RemlinkHelper {
  static func main() async {
    do {
      if CommandLine.arguments.contains("--authorize") {
        let store = EKEventStore()
        guard try await requestRemindersAccess(store) else {
          throw HelperError.remindersAccessDenied
        }
        _ = try runRem(arguments: ["lists", "--output", "json"])
        print("RemlinkHelper reminders access granted.")
        return
      }

      guard let request = try readMessage() else {
        return
      }
      let response = try await handle(request)
      try writeMessage(response)
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      try? writeMessage(NativeResponse(ok: false, tags: nil, error: message))
    }
  }
}

private func readMessage() throws -> NativeRequest? {
  let input = FileHandle.standardInput
  let header = input.readData(ofLength: 4)
  if header.isEmpty {
    return nil
  }
  guard header.count == 4 else {
    throw HelperError.invalidLengthHeader
  }

  let length = header.withUnsafeBytes { rawBuffer -> UInt32 in
    rawBuffer.load(as: UInt32.self).littleEndian
  }
  guard length <= maxMessageSize else {
    throw HelperError.messageTooLarge
  }

  let body = input.readData(ofLength: Int(length))
  return try JSONDecoder().decode(NativeRequest.self, from: body)
}

private func writeMessage(_ response: NativeResponse) throws {
  let data = try JSONEncoder().encode(response)
  var length = UInt32(data.count).littleEndian
  var output = Data(bytes: &length, count: 4)
  output.append(data)
  FileHandle.standardOutput.write(output)
}

private func handle(_ request: NativeRequest) async throws -> NativeResponse {
  switch request.action {
  case "list_tags":
    let tags = try listExistingTags(filter: request.filter ?? "链接")
    return NativeResponse(ok: true, tags: tags, error: nil)
  case "save_link":
    try saveLink(request)
    return NativeResponse(ok: true, tags: nil, error: nil)
  default:
    throw HelperError.invalidRequest
  }
}

private func requestRemindersAccess(_ store: EKEventStore) async throws -> Bool {
  if #available(macOS 14.0, *) {
    return try await store.requestFullAccessToReminders()
  }

  return try await withCheckedThrowingContinuation { continuation in
    store.requestAccess(to: .reminder) { granted, error in
      if let error {
        continuation.resume(throwing: error)
      } else {
        continuation.resume(returning: granted)
      }
    }
  }
}

private func saveLink(_ request: NativeRequest) throws {
  let urlString = (request.url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
  guard !urlString.isEmpty else {
    throw HelperError.missingURL
  }

  let title = normalized(request.title) ?? urlString
  let note = normalized(request.note)
  let tags = normalizeTags(request.tags)

  var arguments = [
    "add",
    title,
    "--list",
    listName,
    "--url",
    urlString,
    "--output",
    "json"
  ]
  if let note {
    arguments += ["--notes", note]
  }
  if !tags.isEmpty {
    arguments += ["--tags", tags.joined(separator: ",")]
  }
  _ = try runRem(arguments: arguments)
}

private func listExistingTags(filter: String) throws -> [String] {
  let output = try runRem(arguments: ["list", "--list", listName, "--output", "json"])
  let data = Data(output.utf8)
  let object = (try? JSONSerialization.jsonObject(with: data)) ?? []
  var tags = Set<String>()
  collectTags(from: object, into: &tags)

  let trimmedFilter = filter.trimmingCharacters(in: .whitespacesAndNewlines)
  let filtered = trimmedFilter.isEmpty ? tags : tags.filter { $0.contains(trimmedFilter) }
  return filtered.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
}

private func normalized(_ value: String?) -> String? {
  let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
  return trimmed.isEmpty ? nil : trimmed
}

private func normalizeTags(_ values: [String]?) -> [String] {
  var result: [String] = []
  for value in values ?? [] {
    let tag = value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    if !tag.isEmpty && !result.contains(tag) {
      result.append(tag)
    }
  }
  return result
}

private func runRem(arguments: [String]) throws -> String {
  let process = Process()
  process.executableURL = try remURL()
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
    throw HelperError.remFailed(error.isEmpty ? output : error)
  }
  return output
}

private func remURL() throws -> URL {
  let helperBundle = Bundle.main.bundleURL
  let appContents = helperBundle.deletingLastPathComponent().deletingLastPathComponent()
  let candidates = [
    appContents.appendingPathComponent("Resources/Remlink_Remlink.bundle/Resources/bin/rem"),
    appContents.appendingPathComponent("Resources/bin/rem"),
    URL(fileURLWithPath: "/Applications/Remlink.app/Contents/Resources/Remlink_Remlink.bundle/Resources/bin/rem")
  ]

  for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
    return candidate
  }
  throw HelperError.remUnavailable
}

private func collectTags(from value: Any, into tags: inout Set<String>) {
  if let dictionary = value as? [String: Any] {
    for (key, child) in dictionary {
      if key == "tags" || key == "hashtags" {
        collectTags(from: child, into: &tags)
      } else if child is [String: Any] || child is [Any] {
        collectTags(from: child, into: &tags)
      }
    }
    return
  }

  if let array = value as? [Any] {
    for item in array {
      collectTags(from: item, into: &tags)
    }
    return
  }

  if let tag = value as? String {
    let cleaned = tag.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    if !cleaned.isEmpty {
      tags.insert(cleaned)
    }
  }
}

private func isRemindersAccessDenied(_ detail: String) -> Bool {
  let lowercased = detail.lowercased()
  return lowercased.contains("reminders access denied")
    || lowercased.contains("failed to initialize reminders access")
    || lowercased.contains("access denied")
}
