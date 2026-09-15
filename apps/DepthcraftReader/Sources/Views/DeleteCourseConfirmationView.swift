import SwiftUI

struct DeleteCourseConfirmationView: View {
    let courseTitle: String
    let packageId: String
    let packageURL: URL
    @Binding var isPresented: Bool
    @EnvironmentObject private var store: CourseStore
    
    @State private var confirmationText = ""
    @FocusState private var isTextFieldFocused: Bool
    
    private var deleteEnabled: Bool {
        confirmationText == "DELETE"
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.red)
                    
                    Text("Delete Course")
                        .font(.title2.weight(.semibold))
                    
                    VStack(spacing: 8) {
                        Text(courseTitle)
                            .font(.body.weight(.medium))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        
                        Text("This action is permanent and cannot be undone. All progress and notes for this course will be deleted.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 24)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Type DELETE to confirm")
                        .font(.subheadline.weight(.medium))
                    
                    TextField("", text: $confirmationText)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .focused($isTextFieldFocused)
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                VStack(spacing: 12) {
                    Button(role: .destructive) {
                        performDelete()
                    } label: {
                        Text("Delete Course")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!deleteEnabled)
                    
                    Button {
                        isPresented = false
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
        .onAppear {
            isTextFieldFocused = true
        }
    }
    
    private func performDelete() {
        do {
            try store.deleteCourse(packageId: packageId, packageURL: packageURL)
            isPresented = false
        } catch {
            print("Failed to delete course: \(error)")
        }
    }
}
