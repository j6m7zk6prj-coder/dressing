import Foundation
import SwiftData
import UIKit

// MARK: - Catégories et listes de choix

enum Category: String, CaseIterable, Identifiable, Codable {
    case jersey, top, jacket, pants, shoes, accessory
    var id: String { rawValue }

    var label: String {
        switch self {
        case .jersey: return "Maillots"
        case .top: return "Hauts"
        case .jacket: return "Vestes"
        case .pants: return "Bas"
        case .shoes: return "Chaussures"
        case .accessory: return "Accessoires"
        }
    }

    var singular: String {
        switch self {
        case .jersey: return "Maillot"
        case .top: return "Haut"
        case .jacket: return "Veste"
        case .pants: return "Bas"
        case .shoes: return "Chaussures"
        case .accessory: return "Accessoire"
        }
    }

    var symbol: String {
        switch self {
        case .jersey: return "soccerball"
        case .top: return "tshirt"
        case .jacket: return "hanger"
        case .pants: return "hanger"
        case .shoes: return "shoeprints.fill"
        case .accessory: return "bag"
        }
    }

    /// Largeur réelle approximative (mètres), pour la penderie 3D.
    var realWidth: Double {
        switch self {
        case .jersey, .top: return 0.56
        case .jacket: return 0.62
        case .pants: return 0.46
        case .shoes: return 0.34
        case .accessory: return 0.28
        }
    }

    /// Accroché sur la tringle.
    var hangs: Bool { [.jersey, .top, .jacket, .pants].contains(self) }

    /// Les photos à prendre pour construire le modèle 3D.
    var requiredViews: [PhotoView] { self == .shoes ? [.side, .top, .front] : [.front, .back] }
    var optionalViews: [PhotoView] { self == .shoes ? [.inner, .rear] : [] }
    var mainView: PhotoView { self == .shoes ? .side : .front }
}

/// Une photo d'un côté de l'habit.
enum PhotoView: String, CaseIterable, Identifiable, Codable {
    case front, back, side, inner, top, rear
    var id: String { rawValue }

    func label(for c: Category) -> String {
        switch self {
        case .front: return c == .shoes ? "Devant (pointe)" : "Devant"
        case .back: return "Dos"
        case .side: return "Profil extérieur"
        case .inner: return "Profil intérieur"
        case .top: return "Dessus"
        case .rear: return "Arrière (talon)"
        }
    }

    func guide(for c: Category) -> String {
        switch self {
        case .front: return c == .shoes
            ? "La pointe face à toi, téléphone à hauteur de la chaussure."
            : "À plat ou sur un cintre, bien de face, tout l’habit dans le cadre."
        case .back: return "Retourne l’habit et prends le dos de la même façon (flocage visible)."
        case .side: return "De profil, pointe vers la gauche, téléphone à hauteur de la semelle."
        case .inner: return "L’autre côté, pointe vers la droite."
        case .top: return "Vue de dessus, pointe vers la gauche, téléphone bien parallèle au sol."
        case .rear: return "Le talon face à toi, à hauteur de la chaussure."
        }
    }

    var symbol: String {
        switch self {
        case .front: return "arrow.down.to.line"
        case .back: return "arrow.uturn.backward"
        case .side: return "arrow.left"
        case .inner: return "arrow.right"
        case .top: return "arrow.down"
        case .rear: return "arrow.up.to.line"
        }
    }
}

enum KitType: String, CaseIterable, Identifiable, Codable {
    case home, away, third, goalkeeper, training, special
    var id: String { rawValue }
    var label: String {
        switch self {
        case .home: return "Domicile"
        case .away: return "Extérieur"
        case .third: return "Third"
        case .goalkeeper: return "Gardien"
        case .training: return "Entraînement"
        case .special: return "Édition spéciale"
        }
    }
}

enum JerseyVersion: String, CaseIterable, Identifiable, Codable {
    case fan, player, retro, matchWorn
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fan: return "Version supporter"
        case .player: return "Version joueur (authentique)"
        case .retro: return "Rétro / vintage"
        case .matchWorn: return "Porté en match"
        }
    }
    var short: String {
        switch self {
        case .fan: return "Supporter"
        case .player: return "Joueur"
        case .retro: return "Rétro"
        case .matchWorn: return "Porté en match"
        }
    }
}

enum Condition: String, CaseIterable, Identifiable, Codable {
    case newTags, new, veryGood, good, worn
    var id: String { rawValue }
    var label: String {
        switch self {
        case .newTags: return "Neuf avec étiquette"
        case .new: return "Neuf sans étiquette"
        case .veryGood: return "Très bon état"
        case .good: return "Bon état"
        case .worn: return "Usé"
        }
    }
}

// MARK: - Un habit

@Model
final class Garment {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var categoryRaw: String = Category.jersey.rawValue
    var name: String = ""
    var brand: String = ""
    var color: String = ""
    var size: String = ""
    var conditionRaw: String = Condition.veryGood.rawValue
    var purchasePrice: Double?
    var value: Double?
    var notes: String = ""
    /// Image détourée (PNG) dans le dossier de l'app.
    var imageFile: String = ""
    var favorite: Bool = false
    /// Les autres photos détourées (dos, dessus, profils…), en JSON { vue: fichier }.
    var viewsData: Data?

    // Maillots
    var club: String = ""
    var season: String = ""
    var kitRaw: String = KitType.home.rawValue
    var player: String = ""
    var number: String = ""
    var versionRaw: String = JerseyVersion.fan.rawValue
    var competition: String = ""
    var signed: Bool = false

    init(category: Category = .jersey) {
        self.categoryRaw = category.rawValue
    }

    var views: [String: String] {
        get { viewsData.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:] }
        set { viewsData = try? JSONEncoder().encode(newValue) }
    }

    /// Le fichier d'une vue (la vue principale est `imageFile`).
    func file(_ v: PhotoView) -> String? {
        if v == category.mainView, !imageFile.isEmpty { return imageFile }
        return views[v.rawValue]
    }

    var allFiles: [String] { [imageFile] + Array(views.values) }

    var category: Category {
        get { Category(rawValue: categoryRaw) ?? .top }
        set { categoryRaw = newValue.rawValue }
    }
    var condition: Condition {
        get { Condition(rawValue: conditionRaw) ?? .veryGood }
        set { conditionRaw = newValue.rawValue }
    }
    var kit: KitType {
        get { KitType(rawValue: kitRaw) ?? .home }
        set { kitRaw = newValue.rawValue }
    }
    var version: JerseyVersion {
        get { JerseyVersion(rawValue: versionRaw) ?? .fan }
        set { versionRaw = newValue.rawValue }
    }

    /// « PSG 2023/24 » pour un maillot, sinon le nom.
    var title: String {
        if category == .jersey {
            let t = [club, season].filter { !$0.isEmpty }.joined(separator: " ")
            if !t.isEmpty { return t }
        }
        if !name.isEmpty { return name }
        return brand.isEmpty ? category.singular : brand
    }

    /// « Domicile · Mbappé 7 » pour un maillot, sinon « Nike · M ».
    var subtitle: String {
        if category == .jersey {
            var parts = [kit.label]
            let flock = [player, number].filter { !$0.isEmpty }.joined(separator: " ")
            if !flock.isEmpty { parts.append(flock) }
            return parts.joined(separator: " · ")
        }
        return [brand, size].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var searchText: String {
        [name, brand, color, club, season, player, number, competition, category.label, kit.label]
            .joined(separator: " ").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}

// MARK: - Images

enum ImageStore {
    static let folder: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Garments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let cache = NSCache<NSString, UIImage>()

    /// Enregistre l'image (max 1400 px de haut) et renvoie le nom du fichier.
    static func save(_ image: UIImage) -> String? {
        let name = UUID().uuidString + ".png"
        let img = image.resized(maxSide: 1400)
        guard let data = img.pngData() else { return nil }
        do {
            try data.write(to: folder.appendingPathComponent(name), options: .atomic)
            return name
        } catch { return nil }
    }

    static func load(_ name: String) -> UIImage? {
        guard !name.isEmpty else { return nil }
        if let img = cache.object(forKey: name as NSString) { return img }
        guard let img = UIImage(contentsOfFile: folder.appendingPathComponent(name).path) else { return nil }
        cache.setObject(img, forKey: name as NSString)
        return img
    }

    /// Version légère pour la 3D.
    static func texture(_ name: String) -> UIImage? {
        let key = ("tex-" + name) as NSString
        if let img = cache.object(forKey: key) { return img }
        guard let img = load(name)?.resized(maxSide: 720) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }

    static func delete(_ name: String) {
        guard !name.isEmpty else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        cache.removeObject(forKey: name as NSString)
        cache.removeObject(forKey: ("tex-" + name) as NSString)
    }
}

extension UIImage {
    /// Redresse l'orientation et réduit la taille.
    func resized(maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

// MARK: - Mise en forme

enum Money {
    static func format(_ v: Double?) -> String {
        guard let v else { return "—" }
        return v.formatted(.currency(code: "EUR").precision(.fractionLength(v.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2)))
    }
}
