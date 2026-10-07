import Foundation

struct AppSettings: Equatable {
    var serverAddress: String = ""
    var username: String = ""
    var password: String = ""

    var isComplete: Bool {
        !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !username.isEmpty &&
        !password.isEmpty
    }
}

enum DocumentDirection: String, Codable, CaseIterable, Identifiable {
    case inDocument = "IN"
    case outDocument = "OUT"

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .inDocument: "Incoming"
        case .outDocument: "Outgoing"
        }
    }
}

struct Clerk: Codable, Equatable, Identifiable, Hashable {
    var id: Int64?
    var name: String
    var phone: String
}

struct DocumentSubject: Codable, Equatable, Identifiable, Hashable {
    var id: Int64?
    var value: String
}

struct Organization: Codable, Equatable, Identifiable, Hashable {
    var id: Int64?
    var name: String
    var hqAddress: String
    var hqPhone: String
    var version: Int64?
}

struct LocationNode: Identifiable, Hashable {
    let location: DocLocation
    var children: [LocationNode]

    var id: String {
        location.id.map(String.init) ?? location.locationPath
    }

    var flattenedLocations: [DocLocation] {
        [location] + children.flatMap(\.flattenedLocations)
    }
}

final class DocLocation: Codable, Identifiable, Hashable {
    var id: Int64?
    var name: String?
    var parent: DocLocation?

    init(id: Int64?, name: String?, parent: DocLocation?) {
        self.id = id
        self.name = name
        self.parent = parent
    }

    var locationPath: String {
        var parts: [String] = []
        var current: DocLocation? = self
        while let item = current {
            if let name = item.name, !name.isEmpty {
                parts.insert(name, at: 0)
            }
            current = item.parent
        }
        return parts.joined(separator: " - ")
    }

    static func == (lhs: DocLocation, rhs: DocLocation) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.parent?.id == rhs.parent?.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(parent?.id)
    }
}

struct DocInfo: Codable, Equatable, Identifiable, Hashable {
    var id: Int64?
    var subject: DocumentSubject?
    var direction: DocumentDirection?
    var organization: Organization?
    var clerk: Clerk?
    var createdAt: Date?
    var comment: String?
    var docLocation: DocLocation?

    var title: String {
        [subject?.value, organization?.name]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
    }
}

struct FileInfo: Codable, Equatable, Identifiable, Hashable {
    var id: Int64?
    var uniqueFileName: String
    var lenght: Int64
    var docInfo: DocInfo?
}

enum DocuStoreError: LocalizedError {
    case missingSettings
    case invalidServerAddress
    case invalidResponse
    case serverStatus(Int)
    case emptyImage

    var errorDescription: String? {
        switch self {
        case .missingSettings: "Please fill server address, username and password in Settings."
        case .invalidServerAddress: "The server address is invalid. Use a host like 192.168.1.130:8088."
        case .invalidResponse: "The server response could not be read."
        case .serverStatus(let code): "The server returned HTTP status \(code)."
        case .emptyImage: "The selected image could not be converted to JPEG."
        }
    }
}

extension JSONDecoder {
    static var docuStore: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = DateFormatters.iso8601WithFractionalSeconds.date(from: value) {
                return date
            }
            if let date = DateFormatters.iso8601.date(from: value) {
                return date
            }
            if let date = DateFormatters.day.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported date format: \(value)"
            )
        }
        return decoder
    }
}

extension JSONEncoder {
    static var docuStore: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(DateFormatters.iso8601WithFractionalSeconds)
        return encoder
    }
}

enum DateFormatters {
    static let iso8601WithFractionalSeconds: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSX"
        return formatter
    }()

    static let iso8601: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssX"
        return formatter
    }()

    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
