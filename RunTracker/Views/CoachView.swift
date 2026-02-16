import SwiftUI
import SwiftData

struct CoachView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CoachingResponse.createdAt, order: .reverse) private var history: [CoachingResponse]
    @StateObject private var coach = ClaudeCoach()

    @State private var selectedTab = 0
    @State private var question = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Command", selection: $selectedTab) {
                    Text("Analyze").tag(0)
                    Text("Weekly").tag(1)
                    Text("Ask").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

                if selectedTab == 2 {
                    HStack {
                        TextField("Ask your coach a question...", text: $question)
                            .textFieldStyle(.roundedBorder)
                        Button("Send") {
                            let q = question
                            question = ""
                            Task { await coach.askCoach(question: q, modelContext: modelContext) }
                        }
                        .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || coach.isLoading)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                } else {
                    Button {
                        Task {
                            if selectedTab == 0 {
                                await coach.analyzeTraining(modelContext: modelContext)
                            } else {
                                await coach.weeklySummary(modelContext: modelContext)
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: selectedTab == 0 ? "chart.bar" : "calendar")
                            Text(selectedTab == 0 ? "Analyze Training" : "Weekly Summary")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(coach.isLoading)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }

                if coach.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Thinking...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = coach.errorMessage {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(error)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let response = coach.latestResponse {
                    ScrollView {
                        Text(response)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if history.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Your AI Coach")
                            .font(.headline)
                        Text("Analyze your training, get weekly summaries,\nor ask a specific question.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section("Recent") {
                            ForEach(history.prefix(10)) { entry in
                                NavigationLink {
                                    ScrollView {
                                        Text(entry.response)
                                            .padding()
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .navigationTitle(entry.command.capitalized)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.command.capitalized)
                                            .font(.headline)
                                        Text(entry.createdAt, style: .relative)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(entry.response.prefix(100) + "...")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Coach")
        }
    }
}

#Preview {
    CoachView()
        .modelContainer(for: [Run.self, UserProfile.self, CoachingResponse.self], inMemory: true)
}
