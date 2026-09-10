import SwiftUI

struct CourseHomeView: View {
    @EnvironmentObject private var store: CourseStore

    var body: some View {
        List {
            if let course = store.course {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(course.manifest.title)
                            .font(.largeTitle.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(course.manifest.topic)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        ProgressView(value: store.courseProgressFraction()) {
                            Text("Course progress")
                        } currentValueLabel: {
                            Text("\(Int(store.courseProgressFraction() * 100))%")
                                .monospacedDigit()
                        }
                        .tint(.teal)

                        if let resume = store.resumeTarget(),
                           let lesson = course.curriculum.lessons[resume.lessonId] {
                            NavigationLink {
                                LessonPlayerView(unitId: resume.unitId, lessonId: resume.lessonId)
                            } label: {
                                Label("Resume · \(lesson.title)", systemImage: "play.fill")
                                    .font(.headline)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.teal)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("Units") {
                    ForEach(store.orderedUnits()) { unit in
                        NavigationLink {
                            UnitView(unitId: unit.id)
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .stroke(Color.teal.opacity(0.25), lineWidth: 4)
                                    Circle()
                                        .trim(from: 0, to: store.unitProgressFraction(unit))
                                        .stroke(Color.teal, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                    if store.progress?.units[unit.id]?.completed == true {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.teal)
                                    } else {
                                        Text("\(unit.order)")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 36, height: 36)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(unit.title)
                                        .font(.headline)
                                    let lessons = store.lessons(for: unit)
                                    let done = lessons.filter { store.progress?.lessons[$0.id]?.completed == true }.count
                                    Text("\(done)/\(lessons.count) lessons")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section {
                    NavigationLink {
                        SettingsStubView()
                    } label: {
                        Label("Settings (BYOK stub)", systemImage: "key")
                    }
                } footer: {
                    Text("Airplane-mode study only — no network required. Progress stays on this device, keyed by packageId.")
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}
