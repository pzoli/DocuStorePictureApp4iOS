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

    func reloadLocations() async throws {
        let client = try makeClient()
        locationTree = try await client.getLocationTree()
        locations = locationTree.flatMap(\.flattenedLocations)
    }

    func reloadSubjects() async throws {
        let client = try makeClient()
        subjects = try await client.getSubjects()
    }

    @discardableResult
    func saveSubject(_ subject: DocumentSubject) async throws -> DocumentSubject {
        let saved = try await makeClient().saveSubject(subject)
        try await reloadSubjects()
        let resolved = if saved.id != nil {
            saved
        } else if let found = subjects.first(where: { $0.value == subject.value }) {
            found
        } else {
            saved
        }
        if selectedDocument?.subject?.id == resolved.id {
            selectedDocument?.subject = resolved
        }
        for index in documents.indices {
            if documents[index].subject?.id == resolved.id {
                documents[index].subject = resolved
            }
        }
        return resolved
    }

    func deleteSubject(_ subject: DocumentSubject) async throws {
        guard let id = subject.id else { return }
        try await makeClient().deleteSubject(id: id)
        try await reloadSubjects()
        if selectedDocument?.subject?.id == id {
            selectedDocument?.subject = nil
        }
        for index in documents.indices {
            if documents[index].subject?.id == id {
                documents[index].subject = nil
            }
        }
    }

    @discardableResult
    func saveLocation(_ location: DocLocation) async throws -> DocLocation {
        let saved = try await makeClient().saveLocation(location)
        try await reloadLocations()
        let resolved = if saved.id != nil {
            saved
        } else if let found = locations.first(where: { $0.name == location.name }) {
            found
        } else {
            saved
        }
        if selectedDocument?.docLocation?.id == resolved.id {
            selectedDocument?.docLocation = resolved
        }
        for index in documents.indices {
            if documents[index].docLocation?.id == resolved.id {
                documents[index].docLocation = resolved
            }
        }
        return resolved
    }

    func deleteLocation(_ location: DocLocation) async throws {
        guard let id = location.id else { return }
        try await makeClient().deleteLocation(id: id)
        try await reloadLocations()
        if selectedDocument?.docLocation?.id == id {
            selectedDocument?.docLocation = nil
        }
        for index in documents.indices {
            if documents[index].docLocation?.id == id {
                documents[index].docLocation = nil
            }
        }
    }

    @discardableResult
    func saveDocument(_ document: DocInfo) async throws -> DocInfo {
        let saved = try await makeClient().saveDocInfo(document)
        if let index = documents.firstIndex(where: { $0.id == saved.id }) {
            documents[index] = saved
        } else {
            documents.insert(saved, at: 0)
        }
        selectedDocument = saved
        return saved
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
