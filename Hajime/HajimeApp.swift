import SwiftUI

@main
struct HajimeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                // 絵に着せる服と髪 (着替えると、どの画面の絵も変わる)
                .environment(\.dressing, model.dressing)
                // 文字はすべて丸ゴシック、ボタンや選択はオレンジ
                .fontDesign(.rounded)
                .tint(Pop.orange)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // 促す通知を予約し直す (7 日分なので、アプリを開くたびに先へ延ばす)
            if phase == .active {
                model.refreshSchedule()
                model.sceneBecameActive()
            } else if phase == .background {
                model.sceneEnteredBackground()
            }
        }
    }
}
