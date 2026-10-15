import SwiftUI

struct LocationSelectionView: View {
    @Bindable var model: AppModel
    var selectedLocation: DocLocation? = nil
    var onSelect: ((DocLocation) -> Void)? = nil
    var onClear: (() -> Void)? = nil
    var isEmbeddedInNavigation: Bool = false

    var body: some View {
        if isEmbeddedInNavigation {
            LocationListContent(
                model: model,
                selectedLocation: selectedLocation,
                onSelect: onSelect,
                onClear: onClear,
                isSheet: false
            )
        } else {
            NavigationStack {
                LocationListContent(
                    model: model,
                    selectedLocation: selectedLocation,
                    onSelect: onSelect,
                    onClear: onClear,
                    isSheet: true
                )
            }
        }
    }
}

private struct LocationListContent: View {
    @Bindable var model: AppModel
    let selectedLocation: DocLocation?
    let onSelect: ((DocLocation) -> Void)?
    let onClear: (() -> Void)?
    let isSheet: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery = ""
    @State private var editingContext: LocationEditingContext?
    @State private var locationPendingDeletion: DocLocation?

    private var isManageMode: Bool {
        onSelect == nil
    }

    private var filteredLocations: [DocLocation] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return model.locations.filter { location in
            let path = location.locationPath
            let name = location.name ?? ""
            return path.localizedCaseInsensitiveContains(trimmed) || name.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        List {
            if !isManageMode, searchQuery.isEmpty, onClear != nil {
                Section {
                    Button {
                        onClear?()
                    } label: {
                        Label("No location", systemImage: selectedLocation == nil ? "checkmark.circle.fill" : "circle")
                    }
                }
            }

            Section("Locations") {
                if !searchQuery.isEmpty {
                    if filteredLocations.isEmpty {
                        ContentUnavailableView.search(text: searchQuery)
                    } else {
                        ForEach(filteredLocations) { location in
                            LocationSearchResultRow(
                                location: location,
                                selectedLocationID: selectedLocation?.id,
                                isManageMode: isManageMode,
                                onSelect: onSelect,
                                onEdit: { loc in
                                    editingContext = LocationEditingContext(locationToEdit: loc, defaultParent: nil)
                                },
                                onAddSublocation: { loc in
                                    editingContext = LocationEditingContext(locationToEdit: nil, defaultParent: loc)
                                },
                                onDelete: { loc in
                                    locationPendingDeletion = loc
                                }
                            )
                        }
                    }
                } else if model.locationTree.isEmpty {
                    ContentUnavailableView(
                        "No locations",
                        systemImage: "archivebox",
                        description: Text("Tap + to add your first location.")
                    )
                } else {
                    ForEach(model.locationTree) { node in
                        LocationNodeRow(
                            node: node,
                            selectedLocationID: selectedLocation?.id,
                            isManageMode: isManageMode,
                            onSelect: onSelect,
                            onEdit: { loc in
                                editingContext = LocationEditingContext(locationToEdit: loc, defaultParent: nil)
                            },
                            onAddSublocation: { loc in
                                editingContext = LocationEditingContext(locationToEdit: nil, defaultParent: loc)
                            },
                            onDelete: { loc in
                                locationPendingDeletion = loc
                            }
                        )
                    }
                }
            }
        }
        .navigationTitle(isManageMode ? "Locations" : "Location")
        .searchable(text: $searchQuery, prompt: "Search locations")
        .refreshable {
            try? await model.reloadLocations()
        }
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingContext = LocationEditingContext(locationToEdit: nil, defaultParent: nil)
                } label: {
                    Label("New Location", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editingContext) { context in
            LocationEditorView(
                model: model,
                locationToEdit: context.locationToEdit,
                defaultParent: context.defaultParent,
                onSaved: { saved in
                    if !isManageMode && context.locationToEdit == nil {
                        onSelect?(saved)
                        dismiss()
                    } else if !isManageMode && context.locationToEdit != nil && selectedLocation?.id == saved.id {
                        onSelect?(saved)
                    }
                }
            )
        }
        .alert(
            "Delete Location",
            isPresented: Binding(
                get: { locationPendingDeletion != nil },
                set: { if !$0 { locationPendingDeletion = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                locationPendingDeletion = nil
            }
            Button("Delete", role: .destructive) {
                if let location = locationPendingDeletion {
                    let deletedID = location.id
                    Task {
                        await model.deleteLocation(location)
                        if selectedLocation?.id == deletedID {
                            onClear?()
                        }
                    }
                }
            }
        } message: {
            if let location = locationPendingDeletion {
                Text("Are you sure you want to delete \"\(location.name ?? location.locationPath)\"?")
            }
        }
        .alert(
            "DocuStore",
            isPresented: Binding(
                get: { model.message != nil },
                set: { if !$0 { model.message = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.message ?? "")
        }
    }
}

private struct LocationNodeRow: View {
    let node: LocationNode
    let selectedLocationID: Int64?
    let isManageMode: Bool
    let onSelect: ((DocLocation) -> Void)?
    let onEdit: (DocLocation) -> Void
    let onAddSublocation: (DocLocation) -> Void
    let onDelete: (DocLocation) -> Void

    var body: some View {
        if node.children.isEmpty {
            rowContent
        } else {
            DisclosureGroup {
                ForEach(node.children) { child in
                    LocationNodeRow(
                        node: child,
                        selectedLocationID: selectedLocationID,
                        isManageMode: isManageMode,
                        onSelect: onSelect,
                        onEdit: onEdit,
                        onAddSublocation: onAddSublocation,
                        onDelete: onDelete
                    )
                }
            } label: {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            if !isManageMode {
                Image(systemName: node.location.id == selectedLocationID ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(node.location.id == selectedLocationID ? Color.accentColor : Color.secondary)
            } else {
                Image(systemName: "folder")
                    .foregroundStyle(Color.accentColor)
            }

            Text(node.location.name ?? node.location.locationPath)
                .foregroundStyle(.primary)

            Spacer()

            Menu {
                Button {
                    onAddSublocation(node.location)
                } label: {
                    Label("Add Sublocation", systemImage: "plus")
                }

                Button {
                    onEdit(node.location)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    onDelete(node.location)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isManageMode {
                onEdit(node.location)
            } else if let onSelect {
                onSelect(node.location)
            }
        }
        .contextMenu {
            Button {
                onAddSublocation(node.location)
            } label: {
                Label("Add Sublocation", systemImage: "plus")
            }

            Button {
                onEdit(node.location)
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDelete(node.location)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDelete(node.location)
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                onEdit(node.location)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .leading) {
            Button {
                onAddSublocation(node.location)
            } label: {
                Label("Add Sublocation", systemImage: "plus")
            }
            .tint(.green)
        }
    }
}

private struct LocationSearchResultRow: View {
    let location: DocLocation
    let selectedLocationID: Int64?
    let isManageMode: Bool
    let onSelect: ((DocLocation) -> Void)?
    let onEdit: (DocLocation) -> Void
    let onAddSublocation: (DocLocation) -> Void
    let onDelete: (DocLocation) -> Void

    var body: some View {
        HStack(spacing: 10) {
            if !isManageMode {
                Image(systemName: location.id == selectedLocationID ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(location.id == selectedLocationID ? Color.accentColor : Color.secondary)
            } else {
                Image(systemName: "folder")
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(location.name ?? "Unnamed")
                    .font(.body)
                    .foregroundStyle(.primary)

                Text(location.locationPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button {
                    onAddSublocation(location)
                } label: {
                    Label("Add Sublocation", systemImage: "plus")
                }

                Button {
                    onEdit(location)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    onDelete(location)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isManageMode {
                onEdit(location)
            } else if let onSelect {
                onSelect(location)
            }
        }
        .contextMenu {
            Button {
                onAddSublocation(location)
            } label: {
                Label("Add Sublocation", systemImage: "plus")
            }

            Button {
                onEdit(location)
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDelete(location)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDelete(location)
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                onEdit(location)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .leading) {
            Button {
                onAddSublocation(location)
            } label: {
                Label("Add Sublocation", systemImage: "plus")
            }
            .tint(.green)
        }
    }
}

private struct LocationEditingContext: Identifiable {
    let id = UUID()
    let locationToEdit: DocLocation?
    let defaultParent: DocLocation?
}

struct LocationEditorView: View {
    @Bindable var model: AppModel
    let locationToEdit: DocLocation?
    let defaultParent: DocLocation?
    var onSaved: ((DocLocation) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var selectedParentID: Int64?
    @State private var isSaving: Bool = false

    private var isEditing: Bool {
        locationToEdit != nil
    }

    private var availableParents: [DocLocation] {
        if let editID = locationToEdit?.id {
            let excludedIDs = excludedDescendantIDs(for: editID, in: model.locationTree)
            return model.locations.filter { loc in
                guard let locID = loc.id else { return false }
                return !excludedIDs.contains(locID)
            }
        }
        return model.locations
    }

    private func excludedDescendantIDs(for locationID: Int64, in nodes: [LocationNode]) -> Set<Int64> {
        for node in nodes {
            if node.location.id == locationID {
                return Set(node.flattenedLocations.compactMap(\.id))
            }
            let childResult = excludedDescendantIDs(for: locationID, in: node.children)
            if !childResult.isEmpty {
                return childResult
            }
        }
        return []
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Location Name", text: $name)

                    Picker("Parent Location", selection: $selectedParentID) {
                        Text("None (Root Level)").tag(nil as Int64?)
                        ForEach(availableParents) { loc in
                            if let id = loc.id {
                                Text(loc.locationPath).tag(id as Int64?)
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Location" : "New Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView("Saving…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .onAppear {
                if let locationToEdit {
                    name = locationToEdit.name ?? ""
                    selectedParentID = locationToEdit.parent?.id
                } else {
                    name = ""
                    selectedParentID = defaultParent?.id
                }
            }
        }
    }

    private func save() {
        Task {
            isSaving = true
            defer { isSaving = false }

            let parentLocation = selectedParentID.flatMap { id in
                model.locations.first(where: { $0.id == id })
            }

            let location = DocLocation(
                id: locationToEdit?.id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                parent: parentLocation
            )

            if let saved = await model.saveLocation(location) {
                onSaved?(saved)
                dismiss()
            }
        }
    }
}
