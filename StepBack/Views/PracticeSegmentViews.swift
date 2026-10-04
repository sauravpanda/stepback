import SwiftData
import SwiftUI
import UIKit

// MARK: - Segments

struct SegmentList: View {
    let segments: [ClipSegment]
    let activeID: UUID?
    let onPlay: (ClipSegment) -> Void
    let onEdit: (ClipSegment) -> Void

    var body: some View {
        if segments.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Patterns")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .padding(.horizontal, 4)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(segments) { segment in
                            SegmentCard(
                                segment: segment,
                                isActive: segment.id == activeID,
                                onPlay: { onPlay(segment) },
                                onEdit: { onEdit(segment) }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

struct SegmentCard: View {
    let segment: ClipSegment
    let isActive: Bool
    let onPlay: () -> Void
    let onEdit: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 10) {
                segmentGlyph
                VStack(alignment: .leading, spacing: 2) {
                    Text(segment.title)
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(SpeedFormatter.timestamp(segment.startSeconds))
                        Text("–")
                        Text(SpeedFormatter.timestamp(segment.endSeconds))
                        if segment.preferredSpeed != 1.0 {
                            Text("·")
                            Text(SpeedFormatter.pill(segment.preferredSpeed))
                        }
                    }
                    .font(Theme.Font.timestamp)
                    .foregroundStyle(Theme.Color.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.Color.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isActive ? Theme.Color.accent : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("Rename", systemImage: "pencil")
            }
        }
    }

    @ViewBuilder
    private var segmentGlyph: some View {
        if let data = segment.thumbnailData, let uiImage = UIImage(data: data) {
            ZStack {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                if isActive {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.Color.accent.opacity(0.4))
                        .frame(width: 36, height: 36)
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? Theme.Color.accent : Color.clear, lineWidth: 1.5)
            )
        } else {
            Image(systemName: isActive ? "waveform" : "play.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isActive ? .black : Theme.Color.accent)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive ? Theme.Color.accent : Theme.Color.accentSoft)
                )
        }
    }
}

struct SegmentSaveSheet: View {
    let defaultSpeed: Double
    let defaultRegion: (start: Double, end: Double)
    let onSave: (String, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var speed: Double

    init(
        defaultSpeed: Double,
        defaultRegion: (start: Double, end: Double),
        onSave: @escaping (String, Double) -> Void
    ) {
        self.defaultSpeed = defaultSpeed
        self.defaultRegion = defaultRegion
        self.onSave = onSave
        _speed = State(initialValue: defaultSpeed)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Pattern name") {
                    TextField("Basic step", text: $title)
                }
                Section("Range") {
                    LabeledContent("Start", value: SpeedFormatter.timestamp(defaultRegion.start))
                        .foregroundStyle(Theme.Color.textSecondary)
                    LabeledContent("End", value: SpeedFormatter.timestamp(defaultRegion.end))
                        .foregroundStyle(Theme.Color.textSecondary)
                    LabeledContent("Length", value: SpeedFormatter.timestamp(max(0, defaultRegion.end - defaultRegion.start)))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                Section("Practice speed") {
                    SpeedPills(selected: speed, onSelect: { speed = $0 })
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.background)
            .navigationTitle("New pattern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed.isEmpty ? "Pattern" : trimmed, speed)
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct SegmentEditSheet: View {
    @Bindable var segment: ClipSegment
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Pattern name", text: $segment.title)
                }
                Section("Range") {
                    LabeledContent("Start", value: SpeedFormatter.timestamp(segment.startSeconds))
                        .foregroundStyle(Theme.Color.textSecondary)
                    LabeledContent("End", value: SpeedFormatter.timestamp(segment.endSeconds))
                        .foregroundStyle(Theme.Color.textSecondary)
                    LabeledContent("Length", value: SpeedFormatter.timestamp(segment.durationSeconds))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                Section("Practice speed") {
                    SpeedPills(selected: segment.preferredSpeed, onSelect: { segment.preferredSpeed = $0 })
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }
                Section("Notes") {
                    TextField("Notes", text: $segment.notes, axis: .vertical)
                        .lineLimit(3...)
                }
                Section {
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Label("Delete pattern", systemImage: "trash")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.background)
            .navigationTitle("Edit pattern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
