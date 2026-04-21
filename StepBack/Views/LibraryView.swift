import AVFoundation
import Photos
import PhotosUI
import SwiftData
import SwiftUI

struct LibraryView: View {

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DanceClip.dateAdded, order: .reverse) private var clips: [DanceClip]

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var importState: ImportState = .idle
    @State private var importError: String?

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
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if clips.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(clips) { clip in
                        NavigationLink {
                            PracticeView(clip: clip)
                        } label: {
                            LibraryCell(clip: clip)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
        }
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
            if clips.isEmpty {
                EmptyView()
            } else {
                importButton
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

    private var importButton: some View {
        PhotosPicker(
            selection: $pickerItems,
            maxSelectionCount: 50,
            matching: .videos,
            preferredItemEncoding: .current
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
}

// MARK: - Cell

private struct LibraryCell: View {
    let clip: DanceClip

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Theme.Color.surfaceElevated
                thumbnail
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        durationBadge
                    }
                }
                .padding(6)
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))

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

#Preview {
    LibraryView()
        .modelContainer(for: [DanceClip.self, Tag.self, LoopMarker.self], inMemory: true)
}
