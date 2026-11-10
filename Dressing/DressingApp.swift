import SwiftData
import SwiftUI

@main
struct DressingApp: App {
    let container: ModelContainer

    init() {
        let demo = Demo.state != nil
        let config = ModelConfiguration(isStoredInMemoryOnly: demo)
        container = try! ModelContainer(for: Garment.self, configurations: config)
        if demo { Demo.seed(container.mainContext) }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Color(red: 0.12, green: 0.42, blue: 0.30))
        }
        .modelContainer(container)
    }
}

/// Deux onglets : la penderie en 3D et la collection.
struct RootView: View {
    @State private var tab = Demo.tab ?? "wardrobe"
    @State private var focusID: UUID?

    var body: some View {
        TabView(selection: $tab) {
            WardrobeView(focusID: $focusID)
                .tabItem { Label("Penderie", systemImage: "hanger") }
                .tag("wardrobe")
            CollectionView { id in
                focusID = id
                tab = "wardrobe"
            }
            .tabItem { Label("Collection", systemImage: "square.grid.2x2") }
            .tag("collection")
        }
    }
}

// MARK: - Données de démonstration (captures d'écran automatiques uniquement)

enum Demo {
    private static func arg(_ name: String) -> String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
        return a[i + 1]
    }
    static var state: String? { arg("-demo") }
    static var tab: String? { arg("-tab") }

    static func image(_ name: String) -> UIImage? {
        for sub in [nil, "Demo", "Resources/Demo"] as [String?] {
            if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: sub) {
                return UIImage(contentsOfFile: url.path)
            }
        }
        return nil
    }

    @MainActor
    static func seed(_ context: ModelContext) {
        struct S { let img: String; let cat: Category; var club = ""; var season = ""; var kit = KitType.home
            var player = ""; var number = ""; var version = JerseyVersion.fan; var name = ""; var brand = ""
            var size = "M"; var paid: Double? = nil; var value: Double? = nil; var fav = false; var signed = false }
        let list: [S] = [
            S(img: "j1", cat: .jersey, club: "Olympique Azur", season: "2024/25", player: "Diallo", number: "10", version: .player, brand: "Kappa", paid: 140, value: 165, fav: true),
            S(img: "j2", cat: .jersey, club: "Real Sierra", season: "2019/20", kit: .away, brand: "Umbro", paid: 75, value: 110),
            S(img: "j3", cat: .jersey, club: "Canaris FC", season: "2008/09", player: "Moreno", number: "9", version: .retro, brand: "Le Coq Sportif", paid: 60, value: 180, signed: true),
            S(img: "j4", cat: .jersey, club: "Celtica", season: "2023/24", brand: "Joma", paid: 85, value: 80),
            S(img: "j5", cat: .jersey, club: "AS Lupa", season: "2001/02", kit: .home, player: "Ricci", number: "10", version: .retro, brand: "Diadora", paid: 120, value: 240, fav: true),
            S(img: "j6", cat: .jersey, club: "Atlético Noche", season: "2022/23", kit: .third, brand: "Hummel", paid: 90, value: 95),
            S(img: "hoodie", cat: .top, name: "Sweat à capuche gris", brand: "Carhartt", size: "L", paid: 89, value: 60),
            S(img: "hoodie2", cat: .jacket, name: "Hoodie kaki", brand: "Stone Island", size: "M", paid: 180, value: 150),
            S(img: "jeans", cat: .pants, name: "Jean brut", brand: "Levi’s", size: "32", paid: 110, value: 80),
            S(img: "shoeA", cat: .shoes, name: "Gel blanches", brand: "Asics", size: "42,5", paid: 140, value: 120),
            S(img: "shoeB", cat: .shoes, name: "Runner noires", brand: "Adidas", size: "43", paid: 120, value: 90),
            S(img: "cap", cat: .accessory, name: "Casquette marine", brand: "New Era", size: "Unique", paid: 35, value: 30),
        ]
        for (i, s) in list.enumerated() {
            let g = Garment(category: s.cat)
            var views: [String: String] = [:]
            if s.cat == .shoes {
                guard let side = image(s.img + "_side"), let f = ImageStore.save(side) else { continue }
                g.imageFile = f
                for v in ["top", "front", "inner", "rear"] {
                    if let im = image(s.img + "_" + v), let f = ImageStore.save(im) { views[v] = f }
                }
            } else {
                guard let img = image(s.img), let file = ImageStore.save(img) else { continue }
                g.imageFile = file
                if let back = image(s.img + "_back"), let f = ImageStore.save(back) { views["back"] = f }
            }
            g.views = views
            g.club = s.club; g.season = s.season; g.kit = s.kit; g.player = s.player; g.number = s.number
            g.version = s.version; g.name = s.name; g.brand = s.brand; g.size = s.size
            g.purchasePrice = s.paid; g.value = s.value; g.favorite = s.fav; g.signed = s.signed
            g.createdAt = Date().addingTimeInterval(Double(-i) * 86_400)
            context.insert(g)
        }
        try? context.save()
    }
}
