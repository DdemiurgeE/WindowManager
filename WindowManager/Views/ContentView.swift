import SwiftUI

struct ContentView: View {
    @EnvironmentObject var windowService: WindowService
    @EnvironmentObject var layoutStorage: LayoutStorageService
    @State private var layoutName = ""
    @State private var showingSaveAlert = false
    @State private var screensInfo = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Window Manager")
                .font(.largeTitle)
                .padding()
            
            // Информация об экранах
            VStack(alignment: .leading, spacing: 10) {
                Text("Screens Information")
                    .font(.headline)
                
                Text(screensInfo)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            .padding()
            
            // Кнопка сохранения layout
            Button("Save Current Layout") {
                showingSaveAlert = true
            }
            .padding()
            
            // Список сохраненных layouts
            LayoutListView()
                .environmentObject(windowService)
                .environmentObject(layoutStorage)
        }
        .padding()
        .frame(minWidth: 400, minHeight: 500)
        .alert("Save Layout", isPresented: $showingSaveAlert) {
            TextField("Layout Name", text: $layoutName)
            Button("Save") {
                saveLayout()
            }
            Button("Cancel", role: .cancel) { }
        }
        .onAppear {
            updateScreensInfo()
        }
    }
    
    private func saveLayout() {
        guard !layoutName.isEmpty else { return }
        
        let windows = windowService.captureCurrentLayout()
        let layout = Layout(name: layoutName, windows: windows)
        layoutStorage.saveLayout(layout)
        
        layoutName = ""
    }
    
    private func updateScreensInfo() {
        screensInfo = windowService.getScreensInfo()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(WindowService())
            .environmentObject(LayoutStorageService())
    }
}
