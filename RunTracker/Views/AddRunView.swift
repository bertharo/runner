import SwiftUI
import SwiftData

struct AddRunView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var distance: String = ""
    @State private var hours: Int = 0
    @State private var minutes: Int = 0
    @State private var seconds: Int = 0
    @State private var date: Date = .now
    @State private var notes: String = ""
    @State private var showingValidationAlert = false
    @State private var validationMessage = ""

    private var totalSeconds: Int {
        hours * 3600 + minutes * 60 + seconds
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Distance") {
                    HStack {
                        TextField("0.00", text: $distance)
                            .keyboardType(.decimalPad)
                        Text("km")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Duration") {
                    HStack {
                        Picker("Hours", selection: $hours) {
                            ForEach(0..<24) { Text("\($0) hr").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)

                        Picker("Minutes", selection: $minutes) {
                            ForEach(0..<60) { Text("\($0) min").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)

                        Picker("Seconds", selection: $seconds) {
                            ForEach(0..<60) { Text("\($0) sec").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: 120)
                }

                Section("Date") {
                    DatePicker("Run Date", selection: $date, displayedComponents: .date)
                }

                Section("Notes") {
                    TextField("Optional notes...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let dist = Double(distance), dist > 0, totalSeconds > 0 {
                    Section("Estimated Pace") {
                        let pace = (Double(totalSeconds) / 60.0) / dist
                        Text(PaceFormatter.formatted(pace: pace))
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                }
            }
            .navigationTitle("Log Run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveRun() }
                        .fontWeight(.semibold)
                }
            }
            .alert("Invalid Input", isPresented: $showingValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
        }
    }

    private func saveRun() {
        guard let dist = Double(distance), dist > 0 else {
            validationMessage = "Please enter a valid distance greater than 0."
            showingValidationAlert = true
            return
        }

        guard totalSeconds > 0 else {
            validationMessage = "Please enter a duration greater than 0."
            showingValidationAlert = true
            return
        }

        let run = Run(distance: dist, duration: totalSeconds, date: date, notes: notes)
        modelContext.insert(run)
        dismiss()
    }
}

#Preview {
    AddRunView()
        .modelContainer(for: Run.self, inMemory: true)
}
