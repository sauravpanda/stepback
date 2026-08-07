import SwiftData
import SwiftUI

enum SettingsKeys {
    static let keepLocalCopies = "keepLocalCopies"
}

/// App settings: whether imports copy video bytes into the sandbox, plus a
/// one-shot way to release the copies that already exist.
struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var clips: [DanceClip]

    @AppStorage(SettingsKeys.keepLocalCopies) private var keepLocalCopies = false

    @State private var copiesBytes: Int64 = 0
    @State private var removeCopiesConfirmation = false

    private var clipsWithCopies: [DanceClip] {
        clips.filter { $0.originalFileName != nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Keep local video copies", isOn: $keepLocalCopies)
                } footer: {
                    Text(
                        """
                        Off: imported clips reference the video in your Photos \
                        library — no extra storage, and renaming or moving it \
                        in Photos is fine, but deleting it there breaks the clip.
                        On: imports also copy the video into StepBack so clips \
                        survive Photos deletions.
                        """
                    )
                }

                if !clipsWithCopies.isEmpty {
                    Section {
                        LabeledContent(
                            "Local copies",
                            value: "\(clipsWithCopies.count) clip\(clipsWithCopies.count == 1 ? "" : "s") · \(formattedBytes)"
                        )
                        Button("Remove All Local Copies", role: .destructive) {
                            removeCopiesConfirmation = true
                        }
                    } footer: {
                        Text(
                            """
                            Clips fall back to their Photos originals. Any clip \
                            whose original was deleted from Photos will stop \
                            playing. Trimmed versions are kept.
                            """
                        )
                    }
                }

                Section {
                } footer: {
                    Text(
                        """
                        Clip metadata (patterns, beats, groups) syncs through \
                        iCloud when StepBack is built with the iCloud \
                        capability enabled.
                        """
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { copiesBytes = OriginalStorage.totalBytes() }
            .confirmationDialog(
                "Remove all local video copies?",
                isPresented: $removeCopiesConfirmation
            ) {
                Button("Remove Copies", role: .destructive) { removeAllCopies() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Frees \(formattedBytes). Clips will play from your Photos library instead.")
            }
        }
    }

    private var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: copiesBytes, countStyle: .file)
    }

    private func removeAllCopies() {
        for clip in clipsWithCopies {
            if let name = clip.originalFileName {
                OriginalStorage.deleteIfExists(name: name)
            }
            clip.originalFileName = nil
        }
        try? modelContext.save()
        copiesBytes = OriginalStorage.totalBytes()
    }
}

#Preview {
    SettingsView()
        .preferredColorScheme(.dark)
}
