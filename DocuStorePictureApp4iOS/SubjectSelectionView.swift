import SwiftUI

struct SubjectSelectionView: View {
    @Bindable var model: AppModel
    var selectedSubject: DocumentSubject? = nil
    var onSelect: ((DocumentSubject) -> Void)? = nil
    var onClear: (() -> Void)? = nil
    var isEmbeddedInNavigation: Bool = false

    var body: some View {
        if isEmbeddedInNavigation {
            SubjectListContent(
                model: model,
                selectedSubject: selectedSubject,
                onSelect: onSelect,
                onClear: onClear,
                isSheet: false
            )
        } else {
            NavigationStack {
                SubjectListContent(
                    model: model,
                    selectedSubject: selectedSubject,
                    onSelect: onSelect,
                    onClear: onClear,
                    isSheet: true
                )
            }
        }
    }
}

private struct SubjectListContent: View {
    @Bindable var model: AppModel
    let selectedSubject: DocumentSubject?
    let onSelect: ((DocumentSubject) -> Void)?
    let onClear: (() -> Void)?
    let isSheet: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery = ""
    @State private var editingContext: SubjectEditingContext?
    @State private var subjectPendingDeletion: DocumentSubject?

    private var isManageMode: Bool {
        onSelect == nil
    }

    private var filteredSubjects: [DocumentSubject] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return model.subjects }
        return model.subjects.filter { subject in
            subject.value.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        List {
            if !isManageMode, searchQuery.isEmpty, onClear != nil {
                Section {
                    Button {
                        onClear?()
                    } label: {
                        Label("No subject", systemImage: selectedSubject == nil ? "checkmark.circle.fill" : "circle")
                    }
                }
            }

            Section("Subjects") {
                if !searchQuery.isEmpty {
                    if filteredSubjects.isEmpty {
                        ContentUnavailableView.search(text: searchQuery)
                    } else {
                        ForEach(filteredSubjects) { subject in
                            SubjectRow(
                                subject: subject,
                                isSelected: selectedSubject?.id == subject.id,
                                isManageMode: isManageMode,
                                onSelect: onSelect,
                                onEdit: { subj in
                                    editingContext = SubjectEditingContext(subjectToEdit: subj)
                                },
                                onDelete: { subj in
                                    subjectPendingDeletion = subj
                                }
                            )
                        }
                    }
                } else if model.subjects.isEmpty {
                    ContentUnavailableView(
                        "No subjects",
                        systemImage: "tag",
                        description: Text("Tap + to add your first subject.")
                    )
                } else {
                    ForEach(model.subjects) { subject in
                        SubjectRow(
                            subject: subject,
                            isSelected: selectedSubject?.id == subject.id,
                            isManageMode: isManageMode,
                            onSelect: onSelect,
                            onEdit: { subj in
                                editingContext = SubjectEditingContext(subjectToEdit: subj)
                            },
                            onDelete: { subj in
                                subjectPendingDeletion = subj
                            }
                        )
                    }
                }
            }
        }
        .navigationTitle(isManageMode ? "Subjects" : "Subject")
        .searchable(text: $searchQuery, prompt: "Search subjects")
        .refreshable {
            try? await model.reloadSubjects()
        }
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingContext = SubjectEditingContext(subjectToEdit: nil)
                } label: {
                    Label("New Subject", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editingContext) { context in
            SubjectEditorView(
                model: model,
                subjectToEdit: context.subjectToEdit,
                onSaved: { saved in
                    if !isManageMode && context.subjectToEdit == nil {
                        onSelect?(saved)
                        dismiss()
                    } else if !isManageMode && context.subjectToEdit != nil && selectedSubject?.id == saved.id {
                        onSelect?(saved)
                    }
                }
            )
        }
        .alert(
            "Delete Subject",
            isPresented: Binding(
                get: { subjectPendingDeletion != nil },
                set: { if !$0 { subjectPendingDeletion = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                subjectPendingDeletion = nil
            }
            Button("Delete", role: .destructive) {
                if let subject = subjectPendingDeletion {
                    let deletedID = subject.id
                    Task {
                        await model.deleteSubject(subject)
                        if selectedSubject?.id == deletedID {
                            onClear?()
                        }
                    }
                }
            }
        } message: {
            if let subject = subjectPendingDeletion {
                Text("Are you sure you want to delete \"\(subject.value)\"?")
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

private struct SubjectRow: View {
    let subject: DocumentSubject
    let isSelected: Bool
    let isManageMode: Bool
    let onSelect: ((DocumentSubject) -> Void)?
    let onEdit: (DocumentSubject) -> Void
    let onDelete: (DocumentSubject) -> Void

    var body: some View {
        HStack(spacing: 10) {
            if !isManageMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            } else {
                Image(systemName: "tag")
                    .foregroundStyle(Color.accentColor)
            }

            Text(subject.value)
                .foregroundStyle(.primary)

            Spacer()

            Menu {
                Button {
                    onEdit(subject)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    onDelete(subject)
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
                onEdit(subject)
            } else if let onSelect {
                onSelect(subject)
            }
        }
        .contextMenu {
            Button {
                onEdit(subject)
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDelete(subject)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDelete(subject)
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                onEdit(subject)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.orange)
        }
    }
}

private struct SubjectEditingContext: Identifiable {
    let id = UUID()
    let subjectToEdit: DocumentSubject?
}

struct SubjectEditorView: View {
    @Bindable var model: AppModel
    let subjectToEdit: DocumentSubject?
    var onSaved: ((DocumentSubject) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var value: String = ""
    @State private var isSaving: Bool = false

    private var isEditing: Bool {
        subjectToEdit != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Subject Name", text: $value)
                }
            }
            .navigationTitle(isEditing ? "Edit Subject" : "New Subject")
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
                    .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
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
                if let subjectToEdit {
                    value = subjectToEdit.value
                } else {
                    value = ""
                }
            }
        }
    }

    private func save() {
        Task {
            isSaving = true
            defer { isSaving = false }

            let subject = DocumentSubject(
                id: subjectToEdit?.id,
                value: value.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            if let saved = await model.saveSubject(subject) {
                onSaved?(saved)
                dismiss()
            }
        }
    }
}
