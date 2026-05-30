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
  let store = EKEventStore()
  guard try await requestRemindersAccess(store) else {
    throw HelperError.remindersAccessDenied
  }

  switch request.action {
  case "list_tags":
    let tags = try await listExistingTags(store: store, filter: request.filter ?? "链接")
    return NativeResponse(ok: true, tags: tags, error: nil)
  case "save_link":
    try saveLink(request, store: store)
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

private func remindersCalendar(store: EKEventStore) throws -> EKCalendar {
  if let existing = store.calendars(for: .reminder).first(where: { $0.title == listName }) {
    return existing
  }

  let calendar = EKCalendar(for: .reminder, eventStore: store)
  calendar.title = listName
  if let source = store.defaultCalendarForNewReminders()?.source ?? store.sources.first(where: { $0.sourceType == .calDAV }) ?? store.sources.first {
    calendar.source = source
  }
  try store.saveCalendar(calendar, commit: true)
  return calendar
}

private func saveLink(_ request: NativeRequest, store: EKEventStore) throws {
  let urlString = (request.url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
  guard !urlString.isEmpty else {
    throw HelperError.missingURL
  }

  let reminder = EKReminder(eventStore: store)
  reminder.calendar = try remindersCalendar(store: store)
  reminder.title = normalized(request.title) ?? urlString
  reminder.url = URL(string: urlString)

  let note = normalized(request.note)
  let tags = normalizeTags(request.tags)
  reminder.notes = makeNotes(url: urlString, note: note, tags: tags)

  try store.save(reminder, commit: true)
}

private func listExistingTags(store: EKEventStore, filter: String) async throws -> [String] {
  let calendar = try remindersCalendar(store: store)
  let predicate = store.predicateForReminders(in: [calendar])
  let allTags = await withCheckedContinuation { continuation in
    store.fetchReminders(matching: predicate) { reminders in
      var tags = Set<String>()
      for reminder in reminders ?? [] {
        collectHashTags(from: reminder.title, into: &tags)
        collectHashTags(from: reminder.notes, into: &tags)
      }
      continuation.resume(returning: tags)
    }
  }

  let trimmedFilter = filter.trimmingCharacters(in: .whitespacesAndNewlines)
  let filtered = trimmedFilter.isEmpty ? allTags : allTags.filter { $0.contains(trimmedFilter) }
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

private func makeNotes(url: String, note: String?, tags: [String]) -> String {
  var parts = [url]
  if let note {
    parts.append(note)
  }
  if !tags.isEmpty {
    parts.append(tags.map { "#\($0)" }.joined(separator: " "))
  }
  return parts.joined(separator: "\n\n")
}

private func collectHashTags(from text: String?, into tags: inout Set<String>) {
  guard let text else {
    return
  }
  let pattern = #"(?<!\S)#([^\s#，,、]+)"#
  guard let regex = try? NSRegularExpression(pattern: pattern) else {
    return
  }
  let range = NSRange(text.startIndex..<text.endIndex, in: text)
  for match in regex.matches(in: text, range: range) {
    guard let tagRange = Range(match.range(at: 1), in: text) else {
      continue
    }
    tags.insert(String(text[tagRange]))
  }
}
