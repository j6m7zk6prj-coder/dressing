import PhotosUI
import SwiftData
import SwiftUI
import Vision
import CoreImage

// MARK: - Détourage automatique (Vision, sur l'iPhone)

enum Cutout {
    static func remove(from image: UIImage) async -> UIImage? {
        let small = image.resized(maxSide: 1800)
        guard let cg = small.cgImage else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do {
                try handler.perform([request])
                guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }
                let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
                let ci = CIImage(cvPixelBuffer: buffer)
                guard let out = CIContext().createCGImage(ci, from: ci.extent) else { return nil }
                return UIImage(cgImage: out)
            } catch {
                return nil
            }
        }.value
    }
}

// MARK: - Ajouter un habit : photo, détourage, infos

struct AddGarmentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var initialCategory: Category = .jersey

    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var original: UIImage?
    @State private var cutout: UIImage?
    @State private var useCutout = true
    @State private var working = false
    @State private var draft = GarmentDraft()

    var body: some View {
        NavigationStack {
            Group {
                if original == nil && !working {
                    chooser
                } else {
                    GarmentForm(draft: $draft, image: shownImage, working: working,
                                hasCutout: cutout != nil, useCutout: $useCutout)
                }
            }
            .navigationTitle("Nouvel habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                if original != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Ajouter") { save() }.disabled(working)
                    }
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        await process(img)
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { img in Task { await process(img) } }
                    .ignoresSafeArea()
            }
            .onAppear {
                draft.category = initialCategory
                if Demo.state == "add", let img = UIImage(named: "Demo/j1") ?? Demo.image("j1") {
                    original = img; cutout = img
                    draft.category = .jersey; draft.club = "Olympique Azur"; draft.season = "2024/25"
                    draft.player = "Diallo"; draft.number = "10"; draft.size = "M"; draft.price = "90"; draft.value = "120"
                }
            }
        }
    }

    private var shownImage: UIImage? { useCutout ? (cutout ?? original) : original }

    private var chooser: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("Prends l’habit en photo").font(.title2.bold())
                Text("Pose-le à plat ou sur un cintre, devant un mur ou un drap uni. Le fond est retiré automatiquement.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            Spacer()
            VStack(spacing: 12) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Prendre une photo", systemImage: "camera").frame(maxWidth: .infinity)
                    }
                    .primaryButton()
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Choisir dans Photos", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                }
                .secondaryButton()
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    private func process(_ image: UIImage) async {
        let img = image.resized(maxSide: 2000)
        original = img
        working = true
        cutout = await Cutout.remove(from: img)
        useCutout = cutout != nil
        working = false
    }

    private func save() {
        guard let img = shownImage, let file = ImageStore.save(img) else { return }
        let g = Garment(category: draft.category)
        draft.apply(to: g)
        g.imageFile = file
        context.insert(g)
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
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

struct GarmentForm: View {
    @Binding var draft: GarmentDraft
    var image: UIImage?
    var working = false
    var hasCutout = false
    @Binding var useCutout: Bool

    var body: some View {
        Form {
            Section {
                ZStack {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 280)
                            .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
                    }
                    if working {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("Détourage…").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .padding(.vertical, 8)
                .listRowBackground(Color(.secondarySystemBackground))
                if hasCutout {
                    Toggle("Fond retiré", isOn: $useCutout)
                } else if !working && image != nil {
                    Text("Le fond n’a pas pu être retiré : la photo sera utilisée telle quelle.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("Catégorie", selection: $draft.category) {
                    ForEach(Category.allCases) { Label($0.singular, systemImage: $0.symbol).tag($0) }
                }
            }

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
