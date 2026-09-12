import SwiftUI

struct MoreMenuView: View {
    @EnvironmentObject private var store: CourseStore
    
    var body: some View {
        List {
            if let course = store.course {
                Section {
                    NavigationLink {
                        GenerationView(extendFromCourse: course)
                    } label: {
                        Text("Extend this Course")
                    }
                    
                    NavigationLink {
                        GenerationView()
                    } label: {
                        Text("Generate New Course")
                    }
                    
                    if !store.availablePackages.isEmpty {
                        NavigationLink {
                            PackageSwitcherView()
                        } label: {
                            Text("Switch Package")
                        }
                    }
                    
                    NavigationLink {
                        SettingsStubView()
                    } label: {
                        Text("Settings")
                    }
                }
            }
        }
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.inline)
    }
}
