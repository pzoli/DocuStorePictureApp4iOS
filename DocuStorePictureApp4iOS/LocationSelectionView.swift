import SwiftUI

struct LocationSelectionView: View {
    let nodes: [LocationNode]
    let selectedLocation: DocLocation?
    let onSelect: (DocLocation) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onClear()
                    } label: {
                        Label("No location", systemImage: selectedLocation == nil ? "checkmark.circle.fill" : "circle")
                    }
                }

                Section("Locations") {
                    if nodes.isEmpty {
                        ContentUnavailableView("No locations", systemImage: "archivebox")
                    } else {
                        ForEach(nodes) { node in
                            LocationNodeRow(
                                node: node,
                                selectedLocationID: selectedLocation?.id,
                                onSelect: onSelect
                            )
                        }
                    }
                }
            }
            .navigationTitle("Location")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

struct LocationNodeRow: View {
    let node: LocationNode
    let selectedLocationID: Int64?
    let onSelect: (DocLocation) -> Void

    var body: some View {
        if node.children.isEmpty {
            locationButton
        } else {
            DisclosureGroup {
                ForEach(node.children) { child in
                    LocationNodeRow(
                        node: child,
                        selectedLocationID: selectedLocationID,
                        onSelect: onSelect
                    )
                }
            } label: {
                locationButton
            }
        }
    }

    private var locationButton: some View {
        Button {
            onSelect(node.location)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: node.location.id == selectedLocationID ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(node.location.id == selectedLocationID ? Color.accentColor : Color.secondary)
                Text(node.location.name ?? node.location.locationPath)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
