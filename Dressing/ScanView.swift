import SceneKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Scan 3D ultra réaliste : importer et ajuster

enum ScanFormats {
    static var types: [UTType] {
        var t: [UTType] = [.usdz]
        if let usd = UTType(filenameExtension: "usd") { t.append(usd) }
        if let obj = UTType(filenameExtension: "obj") { t.append(obj) }
        return t
    }
}

/// Comment faire un scan avec Scaniverse (gratuit, sur iPhone 13, sans LiDAR).
struct ScanHowTo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            step(1, "Installe **Scaniverse** (gratuit) depuis l’App Store.")
            step(2, "Pose l’habit sur un cintre ou une chaussure sur une table, dans une pièce bien éclairée, sans lumière directe.")
            step(3, "Lance un scan d’objet et tourne lentement tout autour, à deux hauteurs (de côté puis un peu au-dessus).")
            step(4, "Une fois traité, choisis **Partager › Exporter › USDZ** puis **Enregistrer dans Fichiers**.")
            step(5, "Reviens ici et importe le fichier.")
        }
        .font(.subheadline)
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "\(n).circle.fill").foregroundStyle(.tint)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ScanSheet: View {
    @Bindable var garment: Garment
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var error: String?
    @State private var model: SCNNode?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            Form {
                if garment.modelFile.isEmpty {
                    Section {
                        ScanHowTo()
                    } header: {
                        Text("Scan 3D ultra réaliste")
                    } footer: {
                        Text("Le scan remplace le modèle fabriqué à partir des photos, dans la penderie et en 3D. Les photos restent utilisées dans la collection.")
                    }
                    Section {
                        Button("Importer un scan (USDZ ou OBJ)", systemImage: "square.and.arrow.down") { importing = true }
                    } footer: {
                        if let error { Text(error).foregroundStyle(.red) }
                    }
                } else {
                    Section {
                        ZStack {
                            if let model {
                                InspectSceneView(item: garment.wardrobeItem, model: model, light: LightSettings.load())
                                    .id(garment.wardrobeItem.scan?.key)
                            } else {
                                ProgressView()
                            }
                        }
                        .frame(height: 320)
                        .listRowInsets(EdgeInsets())
                    } footer: {
                        Text("Tourne autour avec un doigt pour vérifier que l’habit est bien à l’endroit.")
                    }
                    Section("Orientation") {
                        HStack {
                            rotate("Basculer", "rotate.3d", \.modelRotX)
                            rotate("Pivoter", "arrow.triangle.2.circlepath", \.modelRotY)
                            rotate("Incliner", "rotate.right", \.modelRotZ)
                        }
                        .buttonStyle(.bordered)
                    }
                    Section {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Taille")
                                Spacer()
                                Text("\(Int(garment.modelScale * 100)) %").foregroundStyle(.secondary).monospacedDigit()
                            }
                            Slider(value: $garment.modelScale, in: 0.5...1.5, step: 0.01) { editing in
                                if !editing { reload() }
                            }
                        }
                        if garment.category.hangs {
                            Toggle("Ajouter le cintre de l’app", isOn: $garment.modelHanger)
                                .onChange(of: garment.modelHanger) { _, _ in reload() }
                        }
                    } footer: {
                        Text(garment.category == .shoes
                             ? "La taille est calculée d’après la pointure. Ajuste si besoin."
                             : "Désactive le cintre si ton scan contient déjà le tien.")
                    }
                    Section {
                        Button("Remplacer le scan", systemImage: "arrow.triangle.2.circlepath.doc.on.clipboard") { importing = true }
                        Button("Supprimer le scan", systemImage: "trash", role: .destructive) {
                            ImageStore.delete(garment.modelFile)
                            garment.modelFile = ""
                            model = nil
                        }
                    }
                }
            }
            .navigationTitle("Scan 3D")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: ScanFormats.types) { result in
                guard case let .success(url) = result else { return }
                guard let name = ImageStore.saveModel(from: url) else { error = "Impossible de lire ce fichier."; return }
                if !garment.modelFile.isEmpty { ImageStore.delete(garment.modelFile) }
                garment.modelFile = name
                garment.modelRotX = 0; garment.modelRotY = 0; garment.modelRotZ = 0; garment.modelScale = 1
                reload()
            }
            .onAppear { if !garment.modelFile.isEmpty { reload() } }
        }
    }

    private func rotate(_ title: String, _ symbol: String, _ key: ReferenceWritableKeyPath<Garment, Double>) -> some View {
        Button {
            garment[keyPath: key] = (garment[keyPath: key] + .pi / 2).truncatingRemainder(dividingBy: 2 * .pi)
            reload()
        } label: {
            Label(title, systemImage: symbol).labelStyle(.titleAndIcon).font(.footnote).frame(maxWidth: .infinity)
        }
    }

    private func reload() {
        guard let scan = garment.wardrobeItem.scan else { return }
        let category = garment.category, size = garment.size
        model = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let n = ScanLoader.load(scan, category: category, size: size)
            DispatchQueue.main.async { finish(n) }
        }
    }

    private func finish(_ n: SCNNode?) {
        do {
            if let n { model = n; error = nil } else {
                error = "Ce scan n’a pas pu être ouvert. Exporte-le en USDZ depuis Scaniverse."
                ImageStore.delete(garment.modelFile)
                garment.modelFile = ""
            }
        }
    }
}
