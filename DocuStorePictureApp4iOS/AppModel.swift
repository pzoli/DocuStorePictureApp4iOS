import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class AppModel {
    var settings = AppSettings()
    var documents: [DocInfo] = []
    var subjects: [DocumentSubject] = []
    var organizations: [Organization] = []
    var locationTree: [LocationNode] = []
    var locations: [DocLocation] = []
    var files: [FileInfo] = []
    var selectedDocument: DocInfo?
    var selectedImage: UIImage?
    var selectedFileID: Int64?
    var searchTerm = ""
    var isLoading = false
    var isUploading = false
    var message: String?

    private var currentPage = 1
    private var canLoadMore = true

    init() {
        loadSettings()
    }

    func loadSettings() {
        let defaults = UserDefaults.standard
        settings = AppSettings(
            serverAddress: defaults.string(forKey: "serverAddress") ?? "",
            username: defaults.string(forKey: "username") ?? "",
            password: defaults.string(forKey: "password") ?? ""
        )
    }

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(settings.serverAddress, forKey: "serverAddress")
        defaults.set(settings.username, forKey: "username")
        defaults.set(settings.password, forKey: "password")
    }

    func start() async {
        guard settings.isComplete else { return }
        await reloadAll()
    }

    func reloadAll() async {
        await withLoading {
            async let references: Void = loadReferences()
            async let docs: Void = reloadDocuments()
            _ = try await (references, docs)
        }
    }

    func reloadDocuments() async throws {
        currentPage = 1
        canLoadMore = true
        let page = try await fetchDocuments(page: currentPage)
        documents = page
        canLoadMore = !page.isEmpty
    }

    func loadNextPageIfNeeded(current docInfo: DocInfo?) async {
        guard let docInfo, canLoadMore, !isLoading, documents.last?.id == docInfo.id else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            currentPage += 1
            let page = try await fetchDocuments(page: currentPage)
            canLoadMore = !page.isEmpty
            documents.append(contentsOf: page)
        } catch {
            currentPage -= 1
            show(error)
        }
    }

    func loadReferences() async throws {
        let client = try makeClient()
        async let loadedSubjects = client.getSubjects()
        async let loadedOrganizations = client.getOrganizations()
        async let loadedLocationTree = client.getLocationTree()
        subjects = try await loadedSubjects
        organizations = try await loadedOrganizations
        locationTree = try await loadedLocationTree
        locations = locationTree.flatMap(\.flattenedLocations)
    }

    func saveDocument(_ document: DocInfo) async -> DocInfo? {
        do {
            let saved = try await makeClient().saveDocInfo(document)
            if let index = documents.firstIndex(where: { $0.id == saved.id }) {
                documents[index] = saved
            } else {
                documents.insert(saved, at: 0)
            }
            selectedDocument = saved
            message = "Document saved."
            return saved
        } catch {
            show(error)
            return nil
        }
    }

    func delete(_ document: DocInfo) async {
        guard let id = document.id else { return }
        do {
            try await makeClient().deleteDocInfo(id: id)
            documents.removeAll { $0.id == id }
            if selectedDocument?.id == id {
                selectedDocument = nil
                files = []
                selectedImage = nil
            }
            message = "Document deleted."
        } catch {
            show(error)
        }
    }

    func select(_ document: DocInfo) async {
        selectedDocument = document
        selectedImage = nil
        selectedFileID = nil
        await loadFiles(for: document)
    }

    func loadFiles(for document: DocInfo) async {
        guard let id = document.id else { return }
        do {
            files = try await makeClient().getFileInfos(docInfoId: id)
            if let first = files.first {
                await loadImage(first)
            }
        } catch {
            show(error)
        }
    }

    func loadImage(_ fileInfo: FileInfo) async {
        guard let id = fileInfo.id else { return }
        do {
            let data = try await makeClient().getImage(fileInfoId: id)
            selectedImage = UIImage(data: data)
            selectedFileID = id
        } catch {
            show(error)
        }
    }

    func upload(_ image: UIImage) async {
        guard let document = selectedDocument else { return }
        isUploading = true
        defer { isUploading = false }

        do {
            let fileInfo = try await makeClient().uploadImage(image, for: document)
            if !files.contains(where: { $0.id == fileInfo.id }) {
                files.append(fileInfo)
            }
            await loadImage(fileInfo)
            message = "Image uploaded."
        } catch {
            show(error)
        }
    }

    private func fetchDocuments(page: Int) async throws -> [DocInfo] {
        let client = try makeClient()
        let trimmedSearch = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSearch.isEmpty {
            return try await client.getDocInfos(page: page)
        }
        return try await client.getFilteredDocInfos(filter: trimmedSearch, page: page)
    }

    private func withLoading(_ operation: () async throws -> Void) async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await operation()
        } catch {
            show(error)
        }
    }

    private func makeClient() throws -> DocuStoreAPIClient {
        try DocuStoreAPIClient(settings: settings)
    }

    private func show(_ error: Error) {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            message = description
        } else {
            message = error.localizedDescription
        }
    }
}
