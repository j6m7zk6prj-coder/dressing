import PhotosUI
import SwiftData
import SwiftUI
import Vision
import CoreImage

// MARK: - Détourage automatique (Vision, sur l'iPhone)

enum Cutout {
    /// Retire le fond, garde l'objet principal, nettoie les bords et recadre au plus juste.
    static func remove(from image: UIImage, keepAll: Bool = false) async -> UIImage? {
        let small = image.resized(maxSide: 2000)
        guard let cg = small.cgImage else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do {
                try handler.perform([request])
                guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }
                let chosen = keepAll ? result.allInstances : mainInstances(result)
                let maskBuffer = try result.generateScaledMaskForImage(forInstances: chosen, from: handler)
                let source = CIImage(cgImage: cg)
                var mask = CIImage(cvPixelBuffer: maskBuffer)
                // Bords : on rogne d'un pixel et demi (enlève le liseré du fond), puis on adoucit.
                mask = mask.applyingFilter("CIMorphologyMinimum", parameters: ["inputRadius": 1.5])
                    .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 0.9])
                    .cropped(to: source.extent)
                let out = source.applyingFilter("CIBlendWithMask", parameters: [
                    "inputBackgroundImage": CIImage.empty(),
                    "inputMaskImage": mask,
                ])
                let ctx = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
                guard let rendered = ctx.createCGImage(out, from: source.extent, format: .RGBA8,
                                                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { return nil }
                return UIImage(cgImage: trimmed(rendered) ?? rendered)
            } catch {
                return nil
            }
        }.value
    }

    /// L'objet le plus grand et le plus proche du centre (et ceux qui le touchent presque).
    private static func mainInstances(_ r: VNInstanceMaskObservation) -> IndexSet {
        let buf = r.instanceMask
        CVPixelBufferLockBaseAddress(buf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }
        let w = CVPixelBufferGetWidth(buf), h = CVPixelBufferGetHeight(buf)
        let row = CVPixelBufferGetBytesPerRow(buf)
        guard let base = CVPixelBufferGetBaseAddress(buf)?.assumingMemoryBound(to: UInt8.self) else { return r.allInstances }
        var score: [Int: Double] = [:], count: [Int: Int] = [:]
        for y in 0..<h {
            for x in 0..<w {
                let label = Int(base[y * row + x])
                guard label > 0 else { continue }
                let dx = Double(x) / Double(w) - 0.5, dy = Double(y) / Double(h) - 0.5
                score[label, default: 0] += 1.5 - min(1, (dx * dx + dy * dy) * 4)
                count[label, default: 0] += 1
            }
        }
        guard let best = score.max(by: { $0.value < $1.value })?.key else { return r.allInstances }
        let bestCount = Double(count[best] ?? 1)
        // Garde aussi les gros morceaux (ex. les deux chaussures d'une paire).
        let keep = count.filter { $0.key == best || Double($0.value) > bestCount * 0.45 }.map(\.key)
        return IndexSet(keep).intersection(r.allInstances)
    }

    /// Recadre l'image sur la partie non transparente (avec une petite marge).
    static func trimmed(_ cg: CGImage) -> CGImage? {
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h)
        let ok = data.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in stride(from: 0, to: h, by: 1) {
            let r = y * w
            for x in stride(from: 0, to: w, by: 2) where data[r + x] > 40 {
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
        guard maxX > minX, maxY > minY else { return nil }
        let pad = Int(Double(max(maxX - minX, maxY - minY)) * 0.01)
        let rect = CGRect(x: max(0, minX - pad), y: max(0, minY - pad),
                          width: min(w, maxX + pad + 1) - max(0, minX - pad), height: min(h, maxY + pad + 1) - max(0, minY - pad))
        return cg.cropping(to: rect)
    }
}

extension UIImage {
    func flippedHorizontally() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            ctx.cgContext.translateBy(x: size.width, y: 0)
            ctx.cgContext.scaleBy(x: -1, y: 1)
            draw(at: .zero)
        }
    }
}

// MARK: - Une photo d'un côté (originale + détourée)

struct ViewPhoto {
    var original: UIImage
    var cutout: UIImage?
    var useCutout = true
    var image: UIImage { useCutout ? (cutout ?? original) : original }
}

// MARK: - Ajouter un habit : catégorie, photos de chaque côté, infos

struct AddGarmentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var initialCategory: Category = .jersey

    @State private var draft = GarmentDraft()
    @State private var photos: [PhotoView: ViewPhoto] = [:]
    @State private var working: Set<PhotoView> = []
    @State private var target: PhotoView?
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var preview: PhotoView?
    @State private var saving = false
    @State private var scanURL: URL?
    @State private var importingScan = false

    private var views: [PhotoView] { draft.category.requiredViews + draft.category.optionalViews }
    private var ready: Bool {
        let photosOK = scanURL != nil ? photos[draft.category.mainView] != nil : draft.category.requiredViews.allSatisfy { photos[$0] != nil }
        return photosOK && working.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Catégorie", selection: $draft.category) {
                        ForEach(Category.allCases) { Label($0.singular, systemImage: $0.symbol).tag($0) }
                    }
                }
                Section {
                    ForEach(views) { v in photoRow(v) }
                } header: {
                    Text("Photos")
                } footer: {
                    Text(draft.category == .shoes
                         ? "Profil, dessus et devant suffisent : l’app reconstruit la forme de la chaussure à sa taille réelle. Ajoute l’autre côté et l’arrière pour un rendu encore plus fidèle."
                         : "Le devant et le dos servent à fabriquer l’habit en 3D, avec du volume. Pose l’habit sur un fond uni, bien éclairé.")
                }
                Section {
                    if let scanURL {
                        Label(scanURL.lastPathComponent, systemImage: "cube.transparent.fill")
                        Button("Retirer le scan", role: .destructive) { self.scanURL = nil }
                    } else {
                        Button("Importer un scan 3D (USDZ)", systemImage: "cube.transparent") { importingScan = true }
                        DisclosureGroup("Comment faire un scan avec Scaniverse") { ScanHowTo().padding(.vertical, 6) }
                    }
                } header: {
                    Text("Scan 3D ultra réaliste (facultatif)")
                } footer: {
                    Text("Avec un scan, seule la photo principale est demandée : le scan sert de modèle 3D.")
                }
                GarmentFields(draft: $draft)
            }
            .fileImporter(isPresented: $importingScan, allowedContentTypes: ScanFormats.types) { result in
                if case let .success(url) = result { scanURL = url }
            }
            .navigationTitle("Nouvel habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button("Ajouter") { save() }.disabled(!ready)
                    }
                }
            }
            .onChange(of: draft.category) { _, c in
                let allowed = Set(c.requiredViews + c.optionalViews)
                photos = photos.filter { allowed.contains($0.key) }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item, let v = target else { return }
                pickerItem = nil
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        await process(img, for: v)
                    }
                }
            }
            .photosPicker(isPresented: $showLibrary, selection: $pickerItem, matching: .images)
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { img in if let v = target { Task { await process(img, for: v) } } }
                    .ignoresSafeArea()
            }
            .sheet(item: $preview) { v in
                if let p = photos[v] {
                    PhotoReview(view: v, category: draft.category, photo: binding(v, p))
                }
            }
            .onAppear {
                draft.category = initialCategory
                if Demo.state == "add" { demoFill() }
            }
        }
    }

    private func binding(_ v: PhotoView, _ p: ViewPhoto) -> Binding<ViewPhoto> {
        Binding(get: { photos[v] ?? p }, set: { photos[v] = $0 })
    }

    @ViewBuilder private func photoRow(_ v: PhotoView) -> some View {
        let required = draft.category.requiredViews.contains(v)
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                if let p = photos[v] {
                    Image(uiImage: p.image).resizable().scaledToFit().padding(4)
                } else if working.contains(v) {
                    ProgressView()
                } else {
                    Image(systemName: v.symbol).font(.title3).foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(v.label(for: draft.category)).font(.body.weight(.medium))
                    if !required { Text("facultatif").font(.caption).foregroundStyle(.secondary) }
                }
                Text(working.contains(v) ? "Détourage…" : v.guide(for: draft.category))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if photos[v] != nil {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
        .contentShape(Rectangle())
        .overlay {
            Menu { menu(v) } label: { Color.clear.contentShape(Rectangle()) }
        }
    }

    @ViewBuilder private func menu(_ v: PhotoView) -> some View {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            Button("Prendre une photo", systemImage: "camera") { target = v; showCamera = true }
        }
        Button("Choisir dans Photos", systemImage: "photo.on.rectangle") { target = v; showLibrary = true }
        if photos[v] != nil {
            Button("Vérifier le détourage", systemImage: "wand.and.stars") { preview = v }
            Button("Retourner l’image", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                if var p = photos[v] {
                    p.original = p.original.flippedHorizontally()
                    p.cutout = p.cutout?.flippedHorizontally()
                    photos[v] = p
                }
            }
            Button("Supprimer", systemImage: "trash", role: .destructive) { photos[v] = nil }
        }
    }

    private func process(_ image: UIImage, for v: PhotoView) async {
        let img = image.resized(maxSide: 2000)
        working.insert(v)
        let cut = await Cutout.remove(from: img)
        photos[v] = ViewPhoto(original: img, cutout: cut, useCutout: cut != nil)
        working.remove(v)
    }

    private func save() {
        saving = true
        let g = Garment(category: draft.category)
        draft.apply(to: g)
        var views: [String: String] = [:]
        for (v, p) in photos {
            guard let file = ImageStore.save(p.image) else { continue }
            if v == draft.category.mainView { g.imageFile = file } else { views[v.rawValue] = file }
        }
        g.views = views
        if let scanURL, let name = ImageStore.saveModel(from: scanURL) {
            g.modelFile = name
            g.modelHanger = true
        }
        context.insert(g)
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func demoFill() {
        draft.category = .jersey; draft.club = "Olympique Azur"; draft.season = "2024/25"
        draft.player = "Diallo"; draft.number = "10"; draft.size = "M"; draft.price = "90"; draft.value = "120"
        if let f = Demo.image("j1") { photos[.front] = ViewPhoto(original: f, cutout: f) }
        if let b = Demo.image("j1_back") { photos[.back] = ViewPhoto(original: b, cutout: b) }
    }
}

/// Vérifier une photo : détourée ou originale, en grand.
struct PhotoReview: View {
    let view: PhotoView
    let category: Category
    @Binding var photo: ViewPhoto
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(uiImage: photo.image)
                    .resizable()
                    .scaledToFit()
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Checkerboard().opacity(photo.useCutout ? 1 : 0))
                if photo.cutout != nil {
                    Picker("Fond", selection: $photo.useCutout) {
                        Text("Fond retiré").tag(true)
                        Text("Photo d’origine").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                } else {
                    Text("Le fond n’a pas pu être retiré. Reprends la photo devant un fond uni et bien éclairé.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
                }
            }
            .padding(.bottom, 20)
            .navigationTitle(view.label(for: category))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
    }
}

/// Damier gris clair qui montre la transparence.
struct Checkerboard: View {
    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 12
            for y in stride(from: 0, to: size.height, by: s) {
                for x in stride(from: 0, to: size.width, by: s) where (Int(x / s) + Int(y / s)) % 2 == 0 {
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(Color(.tertiarySystemFill)))
                }
            }
        }
    }
}

// MARK: - Les infos d'un habit (ajout et modification)

struct GarmentDraft {
    var category: Category = .jersey
    var name = "", brand = "", color = "", size = "", notes = ""
    var condition: Condition = .veryGood
    var price = "", value = ""
    var club = "", season = "", player = "", number = "", competition = ""
    var kit: KitType = .home
    var version: JerseyVersion = .fan
    var signed = false

    init() {}

    init(_ g: Garment) {
        category = g.category; name = g.name; brand = g.brand; color = g.color; size = g.size; notes = g.notes
        condition = g.condition
        price = g.purchasePrice.map(Self.text) ?? ""
        value = g.value.map(Self.text) ?? ""
        club = g.club; season = g.season; player = g.player; number = g.number; competition = g.competition
        kit = g.kit; version = g.version; signed = g.signed
    }

    func apply(to g: Garment) {
        g.category = category; g.name = name.trimmed; g.brand = brand.trimmed; g.color = color.trimmed
        g.size = size.trimmed; g.notes = notes.trimmed; g.condition = condition
        g.purchasePrice = Self.number(price); g.value = Self.number(value)
        g.club = club.trimmed; g.season = season.trimmed; g.player = player.trimmed; g.number = number.trimmed
        g.competition = competition.trimmed; g.kit = kit; g.version = version; g.signed = signed
    }

    static func number(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "€", with: "").trimmed)
    }

    static func text(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v).replacingOccurrences(of: ".", with: ",")
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Les champs du formulaire (sans les photos).
struct GarmentFields: View {
    @Binding var draft: GarmentDraft

    var body: some View {
        if draft.category == .jersey {
            Section("Maillot") {
                TextField("Club ou sélection", text: $draft.club)
                TextField("Saison (ex. 2024/25)", text: $draft.season)
                Picker("Type", selection: $draft.kit) {
                    ForEach(KitType.allCases) { Text($0.label).tag($0) }
                }
                Picker("Version", selection: $draft.version) {
                    ForEach(JerseyVersion.allCases) { Text($0.label).tag($0) }
                }
            }
            Section("Flocage") {
                TextField("Joueur", text: $draft.player)
                TextField("Numéro", text: $draft.number).keyboardType(.numberPad)
                TextField("Compétition, patchs", text: $draft.competition)
                Toggle("Signé", isOn: $draft.signed)
            }
        } else {
            Section("Habit") {
                TextField("Nom (ex. Sweat à capuche)", text: $draft.name)
                TextField("Couleur", text: $draft.color)
            }
        }

        Section("Détails") {
            TextField("Marque", text: $draft.brand)
            TextField("Taille", text: $draft.size)
            Picker("État", selection: $draft.condition) {
                ForEach(Condition.allCases) { Text($0.label).tag($0) }
            }
        }

        Section {
            HStack {
                Text("Prix payé")
                TextField("0", text: $draft.price).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                Text("€").foregroundStyle(.secondary)
            }
            HStack {
                Text("Valeur actuelle")
                TextField("0", text: $draft.value).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                Text("€").foregroundStyle(.secondary)
            }
        } header: {
            Text("Valeur")
        } footer: {
            Text("La valeur actuelle sert à calculer la valeur de ta collection.")
        }

        Section("Notes") {
            TextField("Où acheté, souvenirs…", text: $draft.notes, axis: .vertical).lineLimit(2...6)
        }
    }
}

struct GarmentForm: View {
    @Binding var draft: GarmentDraft
    var image: UIImage?

    var body: some View {
        Form {
            if let image {
                Section {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 220).padding(.vertical, 8)
                        .listRowBackground(Color(.secondarySystemBackground))
                }
            }
            Section {
                Picker("Catégorie", selection: $draft.category) {
                    ForEach(Category.allCases) { Label($0.singular, systemImage: $0.symbol).tag($0) }
                }
            }
            GarmentFields(draft: $draft)
        }
    }
}

// MARK: - Appareil photo

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
