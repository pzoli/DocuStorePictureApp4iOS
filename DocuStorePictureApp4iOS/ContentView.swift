import PhotosUI
import SwiftUI

struct ContentView: View {
    @State private var model = AppModel()

    var body: some View {
        DocumentListView(model: model)
            .task {
                await model.start()
            }
    }
}

struct DocumentListView: View {
    @Bindable var model: AppModel
    @State private var isShowingSettings = false
    @State private var isShowingEditor = false
    @State private var editingDocument: DocInfo?
    @State private var documentPendingDeletion: DocInfo?

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedDocument) {
                ForEach(model.documents) { document in
                    NavigationLink(value: document) {
                        DocumentRowView(
                            title: document.title,
                            date: document.createdAt,
                            location: document.docLocation?.locationPath,
                            comment: document.comment
                        )
                    }
                    .contextMenu {
                        Button {
                            editingDocument = document
                            isShowingEditor = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            documentPendingDeletion = document
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            documentPendingDeletion = document
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            editingDocument = document
                            isShowingEditor = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.accentColor)
                    }
                    .task {
                        await model.loadNextPageIfNeeded(current: document)
                    }
                }
            }
            .overlay {
                if model.documents.isEmpty && !model.isLoading {
                    ContentUnavailableView("No documents", systemImage: "doc.text.magnifyingglass")
                }
            }
            .navigationTitle("Documents")
            .searchable(text: $model.searchTerm, prompt: "Search")
            .onSubmit(of: .search) {
                Task { try? await model.reloadDocuments() }
            }
            .refreshable {
                try? await model.reloadDocuments()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingDocument = nil
                        isShowingEditor = true
                    } label: {
                        Label("New Document", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let document = model.selectedDocument {
                DocumentDetailView(model: model, document: document)
            } else {
                ContentUnavailableView("Select a document", systemImage: "doc.text.image")
            }
        }
        .onChange(of: model.searchTerm) { _, newValue in
            if newValue.isEmpty {
                Task { try? await model.reloadDocuments() }
            }
        }
        .onChange(of: model.selectedDocument) { _, document in
            if let document {
                Task { await model.select(document) }
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(model: model)
        }
        .sheet(isPresented: $isShowingEditor) {
            DocumentEditorView(model: model, document: editingDocument)
        }
        .alert("Delete document?", isPresented: Binding(
            get: { documentPendingDeletion != nil },
            set: { if !$0 { documentPendingDeletion = nil } }
        )) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let document = documentPendingDeletion {
                    Task { await model.delete(document) }
                }
            }
        } message: {
            Text("This removes the selected document from DocuStore.")
        }
        .alert("DocuStore", isPresented: Binding(
            get: { model.message != nil },
            set: { if !$0 { model.message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.message ?? "")
        }
    }
}

struct DocumentRowView: View {
    let title: String
    let date: Date?
    let location: String?
    let comment: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.isEmpty ? "Untitled document" : title)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 12) {
                if let date {
                    Label {
                        Text(date, format: .dateTime.year().month().day())
                    } icon: {
                        Image(systemName: "calendar")
                    }
                }

                if let location, !location.isEmpty {
                    Label(location, systemImage: "archivebox")
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let comment, !comment.isEmpty {
                Text(comment)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct DocumentDetailView: View {
    @Bindable var model: AppModel
    let document: DocInfo

    @State private var photoSelection: PhotosPickerItem?
    @State private var isShowingCamera = false
    @State private var isShowingEditor = false
    @State private var isConfirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DocumentHeaderView(
                    title: document.title,
                    direction: document.direction,
                    date: document.createdAt,
                    location: document.docLocation?.locationPath,
                    comment: document.comment
                )

                ImagePreviewView(image: model.selectedImage, isUploading: model.isUploading)

                FileStripView(
                    files: model.files,
                    selectedFileID: model.selectedFileID,
                    onSelect: { file in
                        Task { await model.loadImage(file) }
                    }
                )

                ViewThatFits {
                    HStack(spacing: 12) {
                        imageActions
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        imageActions
                    }
                }
            }
            .padding()
        }
        .navigationTitle(document.title.isEmpty ? "Document" : document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                Button {
                    isShowingEditor = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
        }
        .photosPicker(isPresented: Binding(
            get: { false },
            set: { _ in }
        ), selection: $photoSelection, matching: .images)
        .onChange(of: photoSelection) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await model.upload(image)
                }
                photoSelection = nil
            }
        }
        .sheet(isPresented: $isShowingCamera) {
            CameraPicker { image in
                Task { await model.upload(image) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isShowingEditor) {
            DocumentEditorView(model: model, document: document)
        }
        .alert("Delete document?", isPresented: $isConfirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await model.delete(document) }
            }
        } message: {
            Text("This removes the selected document from DocuStore.")
        }
    }

    @ViewBuilder
    private var imageActions: some View {
        Button {
            isShowingCamera = true
        } label: {
            Label("Camera", systemImage: "camera")
        }
        .buttonStyle(.borderedProminent)

        PhotosPicker(selection: $photoSelection, matching: .images) {
            Label("Photo Library", systemImage: "photo.on.rectangle")
        }
        .buttonStyle(.bordered)
    }
}

struct DocumentHeaderView: View {
    let title: String
    let direction: DocumentDirection?
    let date: Date?
    let location: String?
    let comment: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.isEmpty ? "Untitled document" : title)
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                if let direction {
                    Label(String(localized: direction.title), systemImage: direction == .inDocument ? "tray.and.arrow.down" : "tray.and.arrow.up")
                }
                if let date {
                    Label {
                        Text(date, format: .dateTime.year().month().day())
                    } icon: {
                        Image(systemName: "calendar")
                    }
                }
                if let location, !location.isEmpty {
                    Label(location, systemImage: "archivebox")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let comment, !comment.isEmpty {
                Text(comment)
                    .font(.body)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ImagePreviewView: View {
    let image: UIImage?
    let isUploading: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)

            if let image {
                ZoomableDocumentImage(image: image)
            } else {
                ContentUnavailableView("No image", systemImage: "photo")
            }

            if isUploading {
                ProgressView("Uploading")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ZoomableDocumentImage: View {
    let image: UIImage

    @State private var scale = 1.0
    @State private var lastScale = 1.0
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero

    var body: some View {
        GeometryReader { proxy in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .gesture(zoomGesture(in: proxy.size))
                .simultaneousGesture(panGesture(in: proxy.size))
                .onTapGesture(count: 2) {
                    withAnimation(.snappy) {
                        resetZoom()
                    }
                }
                .accessibilityLabel("Document image")
                .accessibilityHint("Pinch to zoom, drag to move, double tap to reset.")
        }
    }

    private func zoomGesture(in size: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, 1), 5)
                offset = clamped(offset, in: size)
            }
            .onEnded { _ in
                lastScale = scale
                offset = clamped(offset, in: size)
                lastOffset = offset
            }
    }

    private func panGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                let proposed = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                offset = clamped(proposed, in: size)
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func clamped(_ offset: CGSize, in size: CGSize) -> CGSize {
        guard scale > 1 else { return .zero }
        let maxX = size.width * (scale - 1) / 2
        let maxY = size.height * (scale - 1) / 2
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    private func resetZoom() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}

struct FileStripView: View {
    let files: [FileInfo]
    let selectedFileID: Int64?
    let onSelect: (FileInfo) -> Void

    var body: some View {
        if !files.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(files) { file in
                        Button {
                            onSelect(file)
                        } label: {
                            Label(file.uniqueFileName, systemImage: "doc.richtext")
                                .labelStyle(.iconOnly)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(file.id == selectedFileID ? .accentColor : nil)
                        .accessibilityLabel(file.uniqueFileName)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

struct DocumentEditorView: View {
    @Bindable var model: AppModel
    let document: DocInfo?

    @Environment(\.dismiss) private var dismiss
    @State private var subject: DocumentSubject?
    @State private var organization: Organization?
    @State private var location: DocLocation?
    @State private var direction: DocumentDirection = .inDocument
    @State private var createdAt = Date()
    @State private var comment = ""
    @State private var isShowingLocationPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Document") {
                    Picker("Subject", selection: $subject) {
                        Text("Select subject").tag(nil as DocumentSubject?)
                        ForEach(model.subjects) { item in
                            Text(item.value).tag(item as DocumentSubject?)
                        }
                    }

                    Picker("Organization", selection: $organization) {
                        Text("Select organization").tag(nil as Organization?)
                        ForEach(model.organizations) { item in
                            Text(item.name).tag(item as Organization?)
                        }
                    }

                    Button {
                        isShowingLocationPicker = true
                    } label: {
                        HStack {
                            Text("Location")
                            Spacer()
                            Text(location?.locationPath ?? "No location")
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .buttonStyle(.plain)

                    Picker("Direction", selection: $direction) {
                        ForEach(DocumentDirection.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)

                    DatePicker("Created", selection: $createdAt, displayedComponents: .date)
                }

                Section("Comment") {
                    TextEditor(text: $comment)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle(document == nil ? "New Document" : "Edit Document")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            let saved = DocInfo(
                                id: document?.id,
                                subject: subject,
                                direction: direction,
                                organization: organization,
                                clerk: document?.clerk,
                                createdAt: createdAt,
                                comment: comment,
                                docLocation: location
                            )
                            if await model.saveDocument(saved) != nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(subject == nil || organization == nil)
                }
            }
            .task {
                try? await model.loadReferences()
            }
            .sheet(isPresented: $isShowingLocationPicker) {
                LocationSelectionView(
                    nodes: model.locationTree,
                    selectedLocation: location,
                    onSelect: { selected in
                        location = selected
                        isShowingLocationPicker = false
                    },
                    onClear: {
                        location = nil
                        isShowingLocationPicker = false
                    }
                )
            }
            .onAppear {
                subject = document?.subject
                organization = document?.organization
                location = document?.docLocation
                direction = document?.direction ?? .inDocument
                createdAt = document?.createdAt ?? Date()
                comment = document?.comment ?? ""
            }
        }
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("192.168.1.130:8088", text: $model.settings.serverAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }

                Section("Login") {
                    TextField("Username", text: $model.settings.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $model.settings.password)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.saveSettings()
                        Task { await model.reloadAll() }
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
