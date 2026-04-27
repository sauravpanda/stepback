import AVFoundation
import Photos
import PhotosUI
import SwiftData
import SwiftUI

struct LibraryView: View {

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DanceClip.dateAdded, order: .reverse) private var clips: [DanceClip]
    @Query(sort: \Tag.name) private var tags: [Tag]

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var importState: ImportState = .idle
    @State private var importError: String?
    @State private var selectedTagIDs: Set<UUID> = []

    @State private var editingClip: DanceClip?
    @State private var isSelecting: Bool = false
    @State private var selectedClipIDs: Set<UUID> = []
    @State private var bulkMovePresented: Bool = false
    @State private var deleteConfirmation: DeleteConfirmation?

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]
    private let photosService: PhotosServicing = PhotosService()

    var body: some View {
        NavigationStack {
            content
                .background(Theme.Color.background.ignoresSafeArea())
                .navigationTitle("Library")
                .toolbarBackground(Theme.Color.background, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar { toolbar }
                .alert(
                    "Import failed",
                    isPresented: .init(
                        get: { importError != nil },
                        set: { if !$0 { importError = nil } }
                    ),
                    presenting: importError
                ) { _ in
                    Button("OK", role: .cancel) { importError = nil }
                } message: { message in
                    Text(message)
                }
                .onChange(of: pickerItems) { _, newItems in
                    guard !newItems.isEmpty else { return }
                    let items = newItems
                    pickerItems = []
                    Task { await importClips(items) }
                }
                .task {
                    _ = await photosService.requestAuthorization()
                }
                .sheet(item: $editingClip) { clip in
                    ClipEditView(clip: clip)
                        .preferredColorScheme(.dark)
                }
                .sheet(isPresented: $bulkMovePresented) {
                    BulkMoveToGroupView(clips: clipsMatching(selectedClipIDs))
                        .preferredColorScheme(.dark)
                        .onDisappear { exitSelectionMode() }
                }
                .confirmationDialog(
                    deleteConfirmation?.title ?? "",
                    isPresented: .init(
                        get: { deleteConfirmation != nil },
                        set: { if !$0 { deleteConfirmation = nil } }
                    ),
                    presenting: deleteConfirmation
                ) { target in
                    Button("Delete", role: .destructive) { commitDelete(target) }
                    Button("Cancel", role: .cancel) { deleteConfirmation = nil }
                } message: { target in
                    Text(target.message)
                }
        }
    }

    private func clipsMatching(_ ids: Set<UUID>) -> [DanceClip] {
        clips.filter { ids.contains($0.id) }
    }

    // MARK: - Content

    private var filteredClips: [DanceClip] {
        guard !selectedTagIDs.isEmpty else { return clips }
        return clips.filter { clip in
            clip.tags.contains { selectedTagIDs.contains($0.id) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if clips.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                if !tags.isEmpty {
                    TagFilterBar(
                        tags: tags,
                        selected: $selectedTagIDs,
                        countFor: { tag in
                            clips.filter { $0.tags.contains(where: { $0.id == tag.id }) }.count
                        }
                    )
                }
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredClips) { clip in
                            clipCell(for: clip)
                        }
                    }
                    .padding(12)
                }
                if isSelecting {
                    bulkActionBar
                }
            }
        }
    }

    @ViewBuilder
    private func clipCell(for clip: DanceClip) -> some View {
        let isSelected = selectedClipIDs.contains(clip.id)
        if isSelecting {
            Button {
                toggleSelection(clip)
            } label: {
                LibraryCell(
                    clip: clip,
                    selectionState: isSelected ? .selected : .unselected,
                    onEdit: nil,
                    onDelete: nil
                )
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                PracticeView(clip: clip)
            } label: {
                LibraryCell(
                    clip: clip,
                    selectionState: .hidden,
                    onEdit: { editingClip = clip },
                    onDelete: { deleteConfirmation = .single(clip) }
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var bulkActionBar: some View {
        HStack(spacing: 12) {
            Text("\(selectedClipIDs.count) selected")
                .font(Theme.Font.bodyEmphasized)
                .foregroundStyle(Theme.Color.textPrimary)
            Spacer()
            Button {
                bulkMovePresented = true
            } label: {
                Label("Move", systemImage: "folder")
                    .font(Theme.Font.bodyEmphasized)
                    .foregroundStyle(Theme.Color.accent)
            }
            .disabled(selectedClipIDs.isEmpty)
            Button(role: .destructive) {
                deleteConfirmation = .bulk(clipsMatching(selectedClipIDs))
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(Theme.Font.bodyEmphasized)
                    .foregroundStyle(.red)
            }
            .disabled(selectedClipIDs.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Theme.Color.surfaceElevated
                .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.Color.divider), alignment: .top)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "film.stack")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.Color.textTertiary)
            Text("Import videos from Photos to start practicing")
                .font(Theme.Font.title)
                .foregroundStyle(Theme.Color.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            importButton
        }
        .padding()
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if isSelecting {
                Button("Done") { exitSelectionMode() }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Color.accent)
            } else if !clips.isEmpty {
                HStack(spacing: 10) {
                    Button {
                        enterSelectionMode()
                    } label: {
                        Text("Select")
                            .foregroundStyle(Theme.Color.textPrimary)
                    }
                    importButton
                }
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            if case .importing(let current, let total) = importState {
                HStack(spacing: 6) {
                    ProgressView()
                    Text("\(current)/\(total)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
        }
    }

    private func enterSelectionMode() {
        isSelecting = true
        selectedClipIDs = []
    }

    private func exitSelectionMode() {
        isSelecting = false
        selectedClipIDs = []
    }

    private func toggleSelection(_ clip: DanceClip) {
        if selectedClipIDs.contains(clip.id) {
            selectedClipIDs.remove(clip.id)
        } else {
            selectedClipIDs.insert(clip.id)
        }
    }

    private var importButton: some View {
        PhotosPicker(
            selection: $pickerItems,
            maxSelectionCount: 50,
            matching: .videos,
            preferredItemEncoding: .current,
            photoLibrary: .shared()
        ) {
            Label("Import", systemImage: "plus")
                .labelStyle(.iconOnly)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Color.accent)
                .padding(8)
                .background(Theme.Color.accentSoft, in: Circle())
        }
        .disabled(importState.isImporting)
    }

    // MARK: - Import

    private func importClips(_ items: [PhotosPickerItem]) async {
        let status = await photosService.requestAuthorization()
        guard status == .authorized || status == .limited else {
            importError = "StepBack needs Photos access to import clips. Enable it in Settings."
            return
        }

        let total = items.count
        importState = .importing(current: 0, total: total)

        var imported = 0
        for (index, item) in items.enumerated() {
            let current = index + 1
            importState = .importing(current: current, total: total)
            do {
                try await importOne(item)
                imported += 1
            } catch {
                importError = "Couldn't import one of \(total) clips: \(error.localizedDescription)"
            }
        }

        importState = .idle
        if imported == 0, importError == nil {
            importError = "No clips imported. Make sure you picked videos, not photos."
        }
        if imported > 0 {
            applyAutoTags()
        }
    }

    /// Re-runs event clustering over all clips and attaches the resulting
    /// \`Event: …\` tags. Existing tags are reused by name; new ones are
    /// inserted. Clips already in the right cluster are left alone.
    private func applyAutoTags() {
        let allClips = clips.sorted { $0.dateAdded < $1.dateAdded }
        let clusters = AutoTagService.cluster(dates: allClips.map(\.dateAdded))
        for cluster in clusters {
            let tag = findOrCreateTag(name: cluster.tagName, colorHex: cluster.colorHex)
            for idx in cluster.indices {
                let clip = allClips[idx]
                if !clip.tags.contains(where: { $0.id == tag.id }) {
                    clip.tags.append(tag)
                }
            }
        }
        try? modelContext.save()
    }

    private func findOrCreateTag(name: String, colorHex: String) -> Tag {
        let descriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.name == name })
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        let tag = Tag(name: name, colorHex: colorHex)
        modelContext.insert(tag)
        return tag
    }

    private func importOne(_ item: PhotosPickerItem) async throws {
        guard let identifier = item.itemIdentifier else {
            throw LibraryError.missingAssetIdentifier
        }
        if clipExists(withAssetIdentifier: identifier) {
            return
        }
        let urlAsset = try await photosService.resolveAVAsset(for: identifier)
        let duration = try await urlAsset.load(.duration).seconds
        let thumbnail = try? await photosService.generateThumbnail(for: urlAsset)
        let title = defaultTitle(for: urlAsset, identifier: identifier)
        let creationDate = creationDate(for: identifier) ?? Date()

        let clip = DanceClip(
            title: title,
            assetIdentifier: identifier,
            dateAdded: creationDate,
            thumbnailData: thumbnail,
            durationSeconds: duration.isFinite ? duration : 0
        )
        modelContext.insert(clip)
        try modelContext.save()
    }

    private func clipExists(withAssetIdentifier identifier: String) -> Bool {
        let descriptor = FetchDescriptor<DanceClip>(
            predicate: #Predicate { $0.assetIdentifier == identifier }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    private func creationDate(for assetIdentifier: String) -> Date? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        return result.firstObject?.creationDate
    }

    private func defaultTitle(for asset: AVURLAsset, identifier: String) -> String {
        let name = asset.url.deletingPathExtension().lastPathComponent
        if !name.isEmpty, name.lowercased() != "videoclip" {
            return name
        }
        return "Clip \(identifier.prefix(6))"
    }

    // MARK: - Delete

    private func commitDelete(_ target: DeleteConfirmation) {
        switch target {
        case .single(let clip):
            modelContext.delete(clip)
        case .bulk(let clips):
            for clip in clips {
                modelContext.delete(clip)
            }
            exitSelectionMode()
        }
        try? modelContext.save()
        deleteConfirmation = nil
    }
}

// MARK: - Cell

enum CellSelectionState {
    case hidden
    case selected
    case unselected
}

private struct LibraryCell: View {
    let clip: DanceClip
    var selectionState: CellSelectionState = .hidden
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Theme.Color.surfaceElevated
                thumbnail
                if selectionState == .selected {
                    Theme.Color.accent.opacity(0.25)
                }
                VStack {
                    HStack {
                        if selectionState != .hidden {
                            selectionIndicator
                        }
                        Spacer()
                        if selectionState == .hidden, onEdit != nil || onDelete != nil {
                            menuButton
                        }
                    }
                    Spacer()
                    HStack {
                        if !clip.tags.isEmpty {
                            tagChips
                        }
                        Spacer()
                        durationBadge
                    }
                }
                .padding(6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius)
                    .stroke(Theme.Color.accent, lineWidth: selectionState == .selected ? 2 : 0)
            )

            Text(clip.title)
                .font(Theme.Font.bodyEmphasized)
                .foregroundStyle(Theme.Color.textPrimary)
                .lineLimit(1)

            Text(clip.dateAdded, style: .date)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textTertiary)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = clip.thumbnailData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            Image(systemName: "film")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.Color.textTertiary)
        }
    }

    private var durationBadge: some View {
        Text(LibraryFormatter.duration(clip.durationSeconds))
            .font(Theme.Font.timestamp)
            .foregroundStyle(Theme.Color.textPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.55), in: Capsule())
    }

    private var selectionIndicator: some View {
        Image(systemName: selectionState == .selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22))
            .foregroundStyle(selectionState == .selected ? Theme.Color.accent : Color.white.opacity(0.85))
            .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
    }

    private var menuButton: some View {
        Menu {
            if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 28, height: 28)
                .background(Color.black.opacity(0.55), in: Circle())
        }
        .menuStyle(.borderlessButton)
    }

    private var tagChips: some View {
        HStack(spacing: 3) {
            ForEach(clip.tags.prefix(3)) { tag in
                Circle()
                    .fill(Color(tagHex: tag.colorHex))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.55), in: Capsule())
    }
}

// MARK: - Tag filter bar

private struct TagFilterBar: View {
    let tags: [Tag]
    @Binding var selected: Set<UUID>
    let countFor: (Tag) -> Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags) { tag in
                    let isSelected = selected.contains(tag.id)
                    let accent = Color(tagHex: tag.colorHex)
                    Button {
                        if isSelected {
                            selected.remove(tag.id)
                        } else {
                            selected.insert(tag.id)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(accent)
                                .frame(width: 8, height: 8)
                            Text(tag.name)
                                .font(.system(.footnote, design: .rounded, weight: .semibold))
                            Text("\(countFor(tag))")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(Theme.Color.textTertiary)
                        }
                        .foregroundStyle(isSelected ? .black : Theme.Color.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(isSelected ? accent : Theme.Color.surfaceElevated)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Theme.Color.background)
    }
}

// MARK: - Formatting

enum LibraryFormatter {
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "--:--" }
        let whole = Int(seconds.rounded())
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

// MARK: - Supporting types

private enum ImportState: Equatable {
    case idle
    case importing(current: Int, total: Int)

    var isImporting: Bool {
        if case .importing = self { return true }
        return false
    }
}

enum LibraryError: Error, LocalizedError {
    case missingAssetIdentifier

    var errorDescription: String? {
        switch self {
        case .missingAssetIdentifier: "The selected item has no asset identifier."
        }
    }
}

enum DeleteConfirmation: Identifiable {
    case single(DanceClip)
    case bulk([DanceClip])

    var id: String {
        switch self {
        case .single(let clip): "single-\(clip.id)"
        case .bulk(let clips): "bulk-" + clips.map(\.id.uuidString).joined(separator: ",")
        }
    }

    var title: String {
        switch self {
        case .single: "Delete this clip?"
        case .bulk(let clips): "Delete \(clips.count) clip\(clips.count == 1 ? "" : "s")?"
        }
    }

    var message: String {
        "The video itself stays in Photos — only StepBack's reference to it is removed."
    }
}

#Preview {
    LibraryView()
        .modelContainer(for: [DanceClip.self, Tag.self, ClipSegment.self], inMemory: true)
}
