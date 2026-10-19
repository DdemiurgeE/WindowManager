import SwiftUI

struct RestorePreviewView: View {
    let layout: Layout
    let planner: RestorePreviewPlanning
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var presentation: RestorePreviewPresentation?
    @State private var showingApplyConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Preview / Dry Run", systemImage: "eye")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Text("No windows will be moved, saved, or marked as used while previewing.")
                .foregroundColor(.secondary)

            if let presentation {
                if let warning = presentation.warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .padding(10)
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(8)
                        .accessibilityAddTraits(.isStaticText)
                }

                if presentation.rows.isEmpty {
                    Text("No windows in this layout.")
                        .foregroundColor(.secondary)
                } else {
                    List(presentation.rows) { row in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("\(row.appName) — \(row.windowTitle)")
                                    .font(.headline)
                                Spacer()
                                Text(row.confidence)
                                    .font(.caption)
                                    .foregroundColor(row.isSkipped ? .orange : .secondary)
                            }
                            Text("Target: \(row.display) · \(row.frame)")
                                .font(.subheadline)
                            Text(row.result)
                                .font(.caption)
                                .foregroundColor(row.isSkipped ? .orange : .secondary)
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                    .listStyle(.inset)
                }

                HStack {
                    Spacer()
                    Button("Apply Layout") {
                        if presentation.warning != nil {
                            showingApplyConfirmation = true
                        } else {
                            onApply()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(presentation.rows.isEmpty)
                    .accessibilityLabel("Apply layout after reviewing preview")
                }
            } else {
                ProgressView("Computing read-only plan…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
        .frame(minWidth: 700, minHeight: 480)
        .onAppear {
            presentation = RestorePreviewModel(planner: planner).presentation(for: layout)
        }
        .confirmationDialog("Some windows cannot be applied safely", isPresented: $showingApplyConfirmation, titleVisibility: .visible) {
            Button("Apply Anyway") { onApply() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Ambiguous matches or incompatible displays will be skipped. Continue with only the safe planned matches?")
        }
    }
}
