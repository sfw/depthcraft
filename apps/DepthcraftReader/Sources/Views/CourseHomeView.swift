import SwiftUI

struct CourseHomeView: View {
    @EnvironmentObject private var store: CourseStore
    @Environment(\.navigationPath) private var navigationPath

    var body: some View {
        List {
            if let course = store.course {
                // Cover band: title, subtitle, colophon
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(course.manifest.title)
                                .font(.system(.title, design: .serif, weight: .semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            if course.manifest.title.localizedCaseInsensitiveCompare(course.manifest.topic) != .orderedSame {
                                Text(course.manifest.topic)
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        // Colophon: lesson count · offline · model
                        let totalLessons = course.curriculum.lessons.count
                        let modelName = course.manifest.generator?.planner.model ?? "Unknown model"
                        Text("\(totalLessons) lessons · offline · \(modelName)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        
                        // Continue button (teal accent)
                        if let resume = store.resumeTarget(),
                           let lesson = course.curriculum.lessons[resume.lessonId] {
                            Button {
                                navigationPath.wrappedValue.append(.lesson(unitId: resume.unitId, lessonId: resume.lessonId))
                            } label: {
                                HStack(spacing: 8) {
                                    Text("Continue")
                                        .font(.subheadline.weight(.medium))
                                    Text("·")
                                        .foregroundStyle(.secondary)
                                    Text(lesson.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.teal)
                            .controlSize(.regular)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color(.systemGroupedBackground))
                
                // Spine: numbered units (clean TOC)
                Section {
                    ForEach(store.orderedUnits()) { unit in
                        NavigationLink(value: NavigationDestination.unit(unitId: unit.id)) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                // Unit number
                                Text("\(unit.order)")
                                    .font(.system(.callout, design: .rounded, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 20, alignment: .trailing)
                                
                                // Current unit marker (teal accent bar)
                                if store.progress?.lastUnitId == unit.id {
                                    Rectangle()
                                        .fill(Color.teal)
                                        .frame(width: 2, height: 16)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(unit.title)
                                        .font(.body)
                                        .foregroundStyle(store.progress?.units[unit.id]?.completed == true ? .secondary : .primary)
                                    
                                    let lessons = store.lessons(for: unit)
                                    let completed = lessons.filter { store.progress?.lessons[$0.id]?.completed == true }.count
                                    if completed > 0 {
                                        Text("\(completed) of \(lessons.count)")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                } header: {
                    Text("Contents")
                        .textCase(nil)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                
                // Demoted actions section (secondary)
                Section {
                    NavigationLink {
                        GenerationView(extendFromCourse: course)
                    } label: {
                        Text("Extend this Course")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    NavigationLink {
                        GenerationView()
                    } label: {
                        Text("Generate New Course")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    if !store.availablePackages.isEmpty {
                        NavigationLink {
                            PackageSwitcherView()
                        } label: {
                            Text("Switch Package")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    NavigationLink {
                        SettingsStubView()
                    } label: {
                        Text("Settings")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if store.course == nil && !store.isLoading {
                // Editorial empty state
                ContentUnavailableView {
                    Label("No Course Loaded", systemImage: "book.closed")
                } description: {
                    Text("Import a course package to begin")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}
