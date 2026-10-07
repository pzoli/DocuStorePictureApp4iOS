import Foundation
import UIKit

final class DocuStoreAPIClient {
    private let settings: AppSettings
    private let session: URLSession

    init(settings: AppSettings) throws {
        guard settings.isComplete else { throw DocuStoreError.missingSettings }
        self.settings = settings
        self.session = URLSession(
            configuration: .ephemeral,
            delegate: InsecureSessionDelegate(),
            delegateQueue: nil
        )
    }

    func getDocInfos(page: Int) async throws -> [DocInfo] {
        try await request(path: "/api/docinfo/page/\(page)", method: "GET")
    }

    func getFilteredDocInfos(filter: String, page: Int) async throws -> [DocInfo] {
        let encodedFilter = filter.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filter
        return try await request(path: "/api/docinfo/filter/\(encodedFilter)/\(page)", method: "GET")
    }

    func getSubjects() async throws -> [DocumentSubject] {
        try await request(path: "/api/subject", method: "GET")
    }

    func getOrganizations() async throws -> [Organization] {
        try await request(path: "/api/organization", method: "GET")
    }

    func getLocations(parentId: Int64 = -1) async throws -> [DocLocation] {
        try await request(path: "/api/doclocation/parent/\(parentId)", method: "GET")
    }

    func getLocationTree(parentId: Int64 = -1) async throws -> [LocationNode] {
        let locations = try await getLocations(parentId: parentId)
        var nodes: [LocationNode] = []

        for location in locations {
            let children: [LocationNode]
            if let id = location.id {
                children = try await getLocationTree(parentId: id)
            } else {
                children = []
            }
            nodes.append(LocationNode(location: location, children: children))
        }

        return nodes
    }

    func saveDocInfo(_ docInfo: DocInfo) async throws -> DocInfo {
        if let id = docInfo.id {
            return try await request(path: "/api/docinfo/\(id)", method: "PUT", body: docInfo)
        }
        return try await request(path: "/api/docinfo", method: "POST", body: docInfo)
    }

    func deleteDocInfo(id: Int64) async throws {
        let _: EmptyResponse = try await request(path: "/api/docinfo/\(id)", method: "DELETE")
    }

    func getFileInfos(docInfoId: Int64) async throws -> [FileInfo] {
        try await request(path: "/api/fileinfo/bydocinfoid/\(docInfoId)", method: "GET")
    }

    func getImage(fileInfoId: Int64) async throws -> Data {
        try await requestData(path: "/api/file/\(fileInfoId)", method: "GET")
    }

    func uploadImage(_ image: UIImage, for docInfo: DocInfo) async throws -> FileInfo {
        guard let imageData = image.jpegData(compressionQuality: 0.86) else {
            throw DocuStoreError.emptyImage
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = try makeURLRequest(path: "/api/file/upload", method: "POST", accept: "application/json")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let docData = try JSONEncoder.docuStore.encode(docInfo)
        let filename = "docustore-\(Int(Date().timeIntervalSince1970)).jpg"
        request.httpBody = MultipartFormDataBuilder(boundary: boundary)
            .addFileField(name: "file", filename: filename, mimeType: "image/jpeg", data: imageData)
            .addDataField(name: "doc", filename: nil, mimeType: "application/json", data: docData)
            .build()

        let data = try await perform(request)
        return try JSONDecoder.docuStore.decode(FileInfo.self, from: data)
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        body: (some Encodable)? = Optional<Int>.none
    ) async throws -> Response {
        var request = try makeURLRequest(path: path, method: method, accept: "application/json")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder.docuStore.encode(body)
        }

        let data = try await perform(request)
        if Response.self == EmptyResponse.self, data.isEmpty {
            return EmptyResponse() as! Response
        }
        return try JSONDecoder.docuStore.decode(Response.self, from: data)
    }

    private func requestData(path: String, method: String) async throws -> Data {
        let request = try makeURLRequest(path: path, method: method, accept: "image/*, application/octet-stream, */*")
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DocuStoreError.invalidResponse
        }

        guard 200...299 ~= httpResponse.statusCode else {
            throw DocuStoreError.serverStatus(httpResponse.statusCode)
        }

        return data
    }

    private func makeURLRequest(path: String, method: String, accept: String) throws -> URLRequest {
        guard var components = URLComponents(string: normalizedBaseURL) else {
            throw DocuStoreError.invalidServerAddress
        }
        components.path = path

        guard let url = components.url else {
            throw DocuStoreError.invalidServerAddress
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        return request
    }

    private var normalizedBaseURL: String {
        let trimmed = settings.serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        return "https://\(trimmed)"
    }

    private var authorizationHeader: String {
        let credentials = "\(settings.username):\(settings.password)"
        let encoded = Data(credentials.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }
}

private struct EmptyResponse: Decodable {}

private final class MultipartFormDataBuilder {
    private let boundary: String
    private var data = Data()

    init(boundary: String) {
        self.boundary = boundary
    }

    func addFileField(name: String, filename: String, mimeType: String, data fieldData: Data) -> MultipartFormDataBuilder {
        appendBoundary()
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        data.append(fieldData)
        append("\r\n")
        return self
    }

    func addDataField(name: String, filename: String?, mimeType: String, data fieldData: Data) -> MultipartFormDataBuilder {
        appendBoundary()
        if let filename {
            append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        } else {
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n")
        }
        append("Content-Type: \(mimeType)\r\n\r\n")
        data.append(fieldData)
        append("\r\n")
        return self
    }

    func build() -> Data {
        append("--\(boundary)--\r\n")
        return data
    }

    private func appendBoundary() {
        append("--\(boundary)\r\n")
    }

    private func append(_ string: String) {
        data.append(Data(string.utf8))
    }
}

private final class InsecureSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    nonisolated func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
