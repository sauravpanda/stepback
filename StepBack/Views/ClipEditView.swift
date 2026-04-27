import SwiftData
import SwiftUI

/// Edit a single clip: title, notes, and group (tag) membership. Also lets
/// the user create a new group inline and assign it.
struct ClipEditView: View {

    @Bindable var clip: DanceClip

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tag.name) private var allTags: [Tag]

    @State private var newGroupName: String = ""
    @FocusState private var newGroupFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Clip title", text: $clip.title)
                        .textInputAutocapitalization(.words)
                }

                Section("Notes") {
                    TextField("What is this clip about?", text: $clip.notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Groups") {
                    if allTags.isEmpty {
                        Text("No groups yet. Create one below.")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textTertiary)
                    } else {
                        ForEach(allTags) { tag in
                            groupRow(for: tag)
                        }
                    }

                    HStack {
                        TextField("New group name", text: $newGroupName)
                            .focused($newGroupFocused)
                            .submitLabel(.done)
                            .onSubmit(addGroup)
                        Button("Add", action: addGroup)
                            .buttonStyle(.borderless)
                            .foregroundStyle(Theme.Color.accent)
                            .disabled(trimmedGroupName.isEmpty)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.background)
            .navigationTitle("Edit clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        try? modelContext.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func groupRow(for tag: Tag) -> some View {
        let isSelected = clip.tags.contains(where: { $0.id == tag.id })
        Button {
            toggle(tag)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(tagHex: tag.colorHex))
                    .frame(width: 10, height: 10)
                Text(tag.name)
                    .foregroundStyle(Theme.Color.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.Color.accent)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private var trimmedGroupName: String {
        newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func toggle(_ tag: Tag) {
        if let index = clip.tags.firstIndex(where: { $0.id == tag.id }) {
            clip.tags.remove(at: index)
        } else {
            clip.tags.append(tag)
        }
    }

    private func addGroup() {
        let name = trimmedGroupName
        guard !name.isEmpty else { return }

        if let existing = allTags.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            if !clip.tags.contains(where: { $0.id == existing.id }) {
                clip.tags.append(existing)
            }
        } else {
            let tag = Tag(name: name, colorHex: "#FF3B7F")
            modelContext.insert(tag)
            clip.tags.append(tag)
        }
        newGroupName = ""
        newGroupFocused = false
    }
}

/// Sheet for moving multiple clips into one group at once.
struct BulkMoveToGroupView: View {

    let clips: [DanceClip]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tag.name) private var allTags: [Tag]

    @State private var newGroupName: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Moving \(clips.count) clip\(clips.count == 1 ? "" : "s") into a group.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                Section("Pick a group") {
                    ForEach(allTags) { tag in
                        Button {
                            assignAll(to: tag)
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color(tagHex: tag.colorHex))
                                    .frame(width: 10, height: 10)
                                Text(tag.name)
                                    .foregroundStyle(Theme.Color.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(Theme.Color.textTertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section("Or create a new group") {
                    HStack {
                        TextField("Group name", text: $newGroupName)
                            .submitLabel(.done)
                            .onSubmit(createAndAssign)
                        Button("Create", action: createAndAssign)
                            .buttonStyle(.borderless)
                            .foregroundStyle(Theme.Color.accent)
                            .disabled(newGroupName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.background)
            .navigationTitle("Move to group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
    }

    private func assignAll(to tag: Tag) {
        for clip in clips where !clip.tags.contains(where: { $0.id == tag.id }) {
            clip.tags.append(tag)
        }
        try? modelContext.save()
        dismiss()
    }

    private func createAndAssign() {
        let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let tag: Tag
        if let existing = allTags.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            tag = existing
        } else {
            tag = Tag(name: name, colorHex: "#FF3B7F")
            modelContext.insert(tag)
        }
        assignAll(to: tag)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: DanceClip.self, Tag.self, LoopMarker.self, ClipSegment.self,
        configurations: .init(isStoredInMemoryOnly: true)
    )
    let clip = DanceClip(title: "Sample", assetIdentifier: "preview")
    container.mainContext.insert(clip)
    return ClipEditView(clip: clip)
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
