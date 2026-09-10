import SwiftUI

struct CurriculumEditorView: View {
    @Binding var curriculum: Curriculum
    @State private var selectedUnitIds: Set<String>
    let onApprove: (Set<String>) -> Void
    let onCancel: () -> Void
    
    init(curriculum: Binding<Curriculum>, onApprove: @escaping (Set<String>) -> Void, onCancel: @escaping () -> Void) {
        self._curriculum = curriculum
        self.onApprove = onApprove
        self.onCancel = onCancel
        self._selectedUnitIds = State(initialValue: Set(curriculum.wrappedValue.units.map { $0.id }))
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Edit unit and lesson titles below. Check units to generate (uncheck to skip for cost control).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Draft Curriculum")
                }
                
                ForEach(Array(curriculum.units.enumerated()), id: \.element.id) { index, unit in
                    Section {
                        unitEditor(unit: binding(for: unit.id), index: index)
                    }
                }
                
                Section {
                    costSummary
                }
                
                Section {
                    Button("Approve & Generate Selected") {
                        approveCurriculum()
                    }
                    .disabled(selectedUnitIds.isEmpty)
                    
                    Button("Cancel", role: .destructive) {
                        onCancel()
                    }
                }
            }
            .navigationTitle("Review Curriculum")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func unitEditor(unit: Binding<CurriculumUnit>, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle(isOn: Binding(
                    get: { selectedUnitIds.contains(unit.wrappedValue.id) },
                    set: { isSelected in
                        if isSelected {
                            selectedUnitIds.insert(unit.wrappedValue.id)
                        } else {
                            selectedUnitIds.remove(unit.wrappedValue.id)
                        }
                    }
                )) {
                    EmptyView()
                }
                .labelsHidden()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unit \(unit.wrappedValue.order)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextField("Unit title", text: unit.title)
                        .font(.headline)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(unit.wrappedValue.lessonIds, id: \.self) { lessonId in
                    if let lessonBinding = lessonBinding(for: lessonId) {
                        lessonEditor(lesson: lessonBinding)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func lessonEditor(lesson: Binding<CurriculumLesson>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("L\(lesson.wrappedValue.order)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                TextField("Lesson title", text: lesson.title, axis: .vertical)
                    .font(.subheadline)
                
                if let minutes = lesson.wrappedValue.estimatedMinutes {
                    Text("\(minutes) min")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private var costSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            let totalUnits = curriculum.units.count
            let selectedCount = selectedUnitIds.count
            let totalLessons = selectedUnitIds.flatMap { unitId in
                curriculum.units.first(where: { $0.id == unitId })?.lessonIds ?? []
            }.count
            
            HStack {
                Text("Units")
                Spacer()
                Text("\(selectedCount) of \(totalUnits) selected")
                    .foregroundStyle(.secondary)
            }
            
            HStack {
                Text("Lessons to generate")
                Spacer()
                Text("\(totalLessons)")
                    .foregroundStyle(.secondary)
            }
            
            if selectedCount < totalUnits {
                Text("Unselected units will be skipped to reduce API costs.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
    
    private func binding(for unitId: String) -> Binding<CurriculumUnit> {
        guard let index = curriculum.units.firstIndex(where: { $0.id == unitId }) else {
            fatalError("Unit not found")
        }
        return $curriculum.units[index]
    }
    
    private func lessonBinding(for lessonId: String) -> Binding<CurriculumLesson>? {
        guard curriculum.lessons.keys.contains(lessonId) else { return nil }
        
        return Binding(
            get: {
                curriculum.lessons[lessonId]!
            },
            set: { newValue in
                curriculum.lessons[lessonId] = newValue
            }
        )
    }
    
    private func approveCurriculum() {
        let generateUnitIds = selectedUnitIds.isEmpty ? nil : Array(selectedUnitIds)
        onApprove(selectedUnitIds)
    }
}
