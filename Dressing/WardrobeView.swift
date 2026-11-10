import SceneKit
import SwiftData
import SwiftUI

// MARK: - Onglet Penderie

struct WardrobeView: View {
    @Query(sort: \Garment.createdAt) private var garments: [Garment]
    @Binding var focusID: UUID?
    @State private var selected: UUID?
    @State private var filter: Category?
    @State private var adding = false
    @State private var detail: Garment?
    @State private var inspecting: Garment?
    @State private var showLight = Demo.state == "light"
    @State private var light = LightSettings.load()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.07, green: 0.065, blue: 0.06).ignoresSafeArea()
                if garments.isEmpty {
                    ContentUnavailableView {
                        Label("Ta penderie est vide", systemImage: "hanger")
                    } description: {
                        Text("Ajoute ton premier habit : il apparaîtra ici, sur son cintre.")
                    } actions: {
                        Button("Ajouter un habit") { adding = true }.primaryButton()
                    }
                    .foregroundStyle(.white)
                } else {
                    WardrobeSceneView(items: items, selected: $selected, light: light)
                        .ignoresSafeArea()
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let id = selected, let g = garments.first(where: { $0.id == id }) {
                    SelectedCard(garment: g, onInspect: { inspecting = g }, onOpen: { detail = g }, onClose: { selected = nil })
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if !garments.isEmpty {
                    Text("Glisse pour parcourir, touche un habit pour le sortir")
                        .font(.footnote)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassPanel(cornerRadius: 20)
                        .padding(.bottom, 10)
                }
            }
            .animation(.smooth(duration: 0.3), value: selected)
            .navigationTitle("Penderie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Afficher", selection: $filter) {
                            Text("Tout").tag(Category?.none)
                            ForEach(Category.allCases) { c in
                                Label(c.label, systemImage: c.symbol).tag(Category?.some(c))
                            }
                        }
                    } label: {
                        Image(systemName: filter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Filtrer")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showLight = true } label: { Image(systemName: "lightbulb") }
                        .accessibilityLabel("Lumière")
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Ajouter un habit")
                }
            }
            .sheet(isPresented: $adding) { AddGarmentView() }
            .sheet(isPresented: $showLight) {
                LightingSheet(settings: $light)
                    .presentationDetents([.medium, .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
            .sheet(item: $detail) { g in
                NavigationStack { GarmentDetailView(garment: g, onShowInWardrobe: nil) }
            }
            .fullScreenCover(item: $inspecting) { g in InspectView(garment: g, light: light) }
            .onChange(of: light) { _, l in l.save() }
            .onChange(of: focusID) { _, id in
                if let id { filter = nil; selected = id; focusID = nil }
            }
            .onAppear {
                if Demo.state == "selected" { selected = garments.first(where: { $0.category == .jersey })?.id }
                if Demo.state == "shoe" { selected = garments.first(where: { $0.category == .shoes })?.id }
                if Demo.state == "inspect" { inspecting = garments.first(where: { $0.category == .shoes }) }
                if Demo.state == "inspectj" { inspecting = garments.first(where: { $0.category == .jersey }) }
            }
        }
    }

    private var items: [WardrobeItem] {
        garments.filter { filter == nil || $0.category == filter }.map(\.wardrobeItem)
    }
}

extension Garment {
    var wardrobeItem: WardrobeItem {
        var files: [PhotoView: String] = [:]
        for v in PhotoView.allCases { if let f = file(v) { files[v] = f } }
        return WardrobeItem(id: id, category: category, files: files, size: size)
    }
}

/// La fiche résumée de l'habit sorti de la penderie.
struct SelectedCard: View {
    let garment: Garment
    var onInspect: () -> Void
    var onOpen: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(garment.title).font(.headline).lineLimit(1)
                    Text(garment.subtitle.isEmpty ? garment.category.singular : garment.subtitle)
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if let v = garment.value ?? garment.purchasePrice {
                    Text(Money.format(v)).font(.headline.monospacedDigit())
                }
                Button(action: onClose) { Image(systemName: "xmark") }
                    .secondaryButton()
                    .accessibilityLabel("Remettre à sa place")
            }
            HStack(spacing: 10) {
                Button(action: onInspect) {
                    Label("En 3D", systemImage: "rotate.3d").lineLimit(1).frame(maxWidth: .infinity)
                }
                .primaryButton()
                Button(action: onOpen) { Text("Fiche").frame(maxWidth: .infinity) }
                    .secondaryButton()
            }
            .controlSize(.large)
            Text("Fais glisser pour le faire tourner")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .glassPanel(cornerRadius: 26)
    }
}

// MARK: - Réglages de lumière

struct LightingSheet: View {
    @Binding var settings: LightSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Ambiances") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(LightSettings.presets.enumerated()), id: \.offset) { _, p in
                                Button(p.0) { withAnimation { settings = p.1 } }
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                                    .tint(settings == p.1 ? Color.accentColor : Color.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                Section("Spots") {
                    slider("Intensité", value: $settings.intensity, in: 0.1...2, format: { "\(Int($0 * 100)) %" })
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Couleur")
                            Spacer()
                            Text("\(Int(settings.temperature)) K").foregroundStyle(.secondary).monospacedDigit()
                        }
                        Slider(value: $settings.temperature, in: 2400...7000, step: 100) {
                            Text("Température")
                        } minimumValueLabel: {
                            Text("Chaude").font(.caption).foregroundStyle(.orange)
                        } maximumValueLabel: {
                            Text("Froide").font(.caption).foregroundStyle(.blue)
                        }
                    }
                }
                Section("Bande LED") {
                    Toggle("Allumée", isOn: $settings.ledOn)
                    ColorPicker("Couleur des LED", selection: ledColor, supportsOpacity: false)
                        .disabled(!settings.ledOn)
                }
                Section {
                    slider("Lumière de la pièce", value: $settings.ambient, in: 0...1.5, format: { "\(Int($0 * 100)) %" })
                    slider("Exposition", value: $settings.exposure, in: -2...1, format: { String(format: "%+.1f", $0) })
                } header: {
                    Text("Pièce et caméra")
                } footer: {
                    Text("Si les habits paraissent trop blancs, baisse l’exposition ou l’intensité.")
                }
                Section {
                    Button("Réglages d’origine") { withAnimation { settings = LightSettings() } }
                }
            }
            .navigationTitle("Lumière")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
    }

    private var ledColor: Binding<Color> {
        Binding(get: { Color(uiColor: settings.led) }, set: { c in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
            settings.ledColor = [Double(r), Double(g), Double(b)].map { max(0, min(1, $0)) }
        })
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, format: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value.wrappedValue)).foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: value, in: range)
        }
    }
}

// MARK: - Inspecter un habit en 3D, en plein écran

struct InspectView: View {
    let garment: Garment
    let light: LightSettings
    @Environment(\.dismiss) private var dismiss
    @State private var model: SCNNode?
    @State private var failed = false

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.08, green: 0.075, blue: 0.07).ignoresSafeArea()
            if let model {
                InspectSceneView(item: garment.wardrobeItem, model: model, light: light)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 12) {
                    if failed {
                        Text("Impossible de construire le modèle 3D avec ces photos.").foregroundStyle(.white)
                    } else {
                        ProgressView().tint(.white)
                        Text("Construction du modèle 3D…").font(.subheadline).foregroundStyle(.white.opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(garment.title).font(.headline)
                    Text(garment.subtitle.isEmpty ? garment.category.singular : garment.subtitle)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .secondaryButton()
                    .controlSize(.large)
                    .accessibilityLabel("Fermer")
            }
            .padding(16)
            .glassPanel(cornerRadius: 24)
            .padding(.horizontal, 12)
            .environment(\.colorScheme, .dark)
        }
        .onAppear {
            ModelFactory.load(garment.wardrobeItem) { n in
                if let n { model = n } else { failed = true }
            }
        }
        .overlay(alignment: .bottom) {
            Text("Un doigt pour tourner · deux doigts pour zoomer ou déplacer · double-touche pour recentrer")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
    }
}

struct InspectSceneView: UIViewRepresentable {
    let item: WardrobeItem
    let model: SCNNode
    let light: LightSettings

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        let scene = SCNScene()
        scene.lightingEnvironment.contents = Materials.tex("studio_env.jpg")
        scene.lightingEnvironment.intensity = 0.9 * CGFloat(max(0.3, light.ambient))
        scene.background.contents = UIColor(red: 0.08, green: 0.075, blue: 0.07, alpha: 1)

        let holder = SCNNode()
        do {
            if item.category.hangs {
                let hanger = HangerModel.make(width: item.category == .pants ? 0.38 : 0.43)
                holder.addChildNode(hanger)
                model.position = SCNVector3(0, -0.052, 0)
            }
            holder.addChildNode(model)
        }
        let (minB, maxB) = holder.boundingBox
        let center = SCNVector3((minB.x + maxB.x) / 2, (minB.y + maxB.y) / 2, (minB.z + maxB.z) / 2)
        holder.position = SCNVector3(-center.x, -minB.y, -center.z)
        if item.category == .shoes { holder.eulerAngles.y = -0.6 }
        scene.rootNode.addChildNode(holder)
        let size = max(maxB.x - minB.x, maxB.y - minB.y, maxB.z - minB.z)

        // Sol sombre légèrement réfléchissant, qui reçoit l'ombre.
        let floor = SCNFloor()
        floor.reflectivity = 0.06
        floor.reflectionFalloffEnd = 0.3
        floor.firstMaterial = Materials.plain(UIColor(white: 0.12, alpha: 1), roughness: 0.6)
        let floorNode = SCNNode(geometry: floor)
        floorNode.position.y = item.category.hangs ? -0.02 : 0
        if item.category.hangs { floorNode.position.y = -0.4 }
        scene.rootNode.addChildNode(floorNode)

        let key = SCNLight()
        key.type = .spot
        key.intensity = 650 * CGFloat(light.intensity)
        key.temperature = CGFloat(light.temperature)
        key.spotOuterAngle = 70
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowSampleCount = 16
        key.shadowRadius = 6
        key.shadowColor = UIColor(white: 0, alpha: 0.55)
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(size * 1.2, size * 2.6 + 0.5, size * 2)
        keyNode.look(at: SCNVector3(0, (maxB.y - minB.y) / 2, 0))
        scene.rootNode.addChildNode(keyNode)
        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 260 * CGFloat(light.intensity)
        rim.color = light.ledOn ? light.led : UIColor.white
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.eulerAngles = SCNVector3(-0.4, .pi * 0.85, 0)
        scene.rootNode.addChildNode(rimNode)

        let cam = SCNCamera()
        cam.fieldOfView = 40
        cam.zNear = 0.01
        cam.wantsHDR = true
        cam.exposureOffset = CGFloat(light.exposure)
        cam.screenSpaceAmbientOcclusionIntensity = 0.8
        let camNode = SCNNode()
        camNode.camera = cam
        let h = maxB.y - minB.y
        let dist = max(0.35, size * 2.1)
        camNode.position = SCNVector3(0, h * 0.55 + dist * 0.12, dist)
        camNode.look(at: SCNVector3(0, h * 0.5, 0))
        scene.rootNode.addChildNode(camNode)

        v.scene = scene
        v.pointOfView = camNode
        v.allowsCameraControl = true
        v.defaultCameraController.interactionMode = .orbitTurntable
        v.defaultCameraController.inertiaEnabled = true
        v.defaultCameraController.target = SCNVector3(0, h * 0.5, 0)
        v.defaultCameraController.minimumVerticalAngle = -10
        v.defaultCameraController.maximumVerticalAngle = 80
        v.antialiasingMode = .multisampling4X
        v.backgroundColor = UIColor(red: 0.08, green: 0.075, blue: 0.07, alpha: 1)
        if Demo.state?.hasPrefix("inspect") == true { camNode.position = SCNVector3(dist * 0.6, h * 0.55 + dist * 0.2, dist * 0.8); camNode.look(at: SCNVector3(0, h * 0.5, 0)) }
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {}
}

// MARK: - La vue SceneKit de la penderie et les gestes

struct WardrobeSceneView: UIViewRepresentable {
    let items: [WardrobeItem]
    @Binding var selected: UUID?
    let light: LightSettings

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = context.coordinator.world.scene
        v.pointOfView = context.coordinator.world.cameraNode
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 60
        v.backgroundColor = UIColor(red: 0.07, green: 0.065, blue: 0.06, alpha: 1)
        v.rendersContinuously = false
        let c = context.coordinator
        v.addGestureRecognizer(UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan(_:))))
        v.addGestureRecognizer(UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.pinch(_:))))
        v.addGestureRecognizer(UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:))))
        c.view = v
        c.world.build(items)
        c.built = items
        c.world.apply(light)
        let screen = UIScreen.main.bounds
        c.world.viewAspect = Float(screen.width / max(1, screen.height))
        if let s = selected { c.world.select(s) }
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        let c = context.coordinator
        c.parent = self
        if c.built != items {
            c.world.build(items)
            c.built = items
        }
        if c.light != light { c.world.apply(light); c.light = light }
        if v.bounds.height > 0 { c.world.viewAspect = Float(v.bounds.width / v.bounds.height) }
        if c.world.selected != selected { c.world.select(selected) }
    }

    final class Coordinator: NSObject {
        var parent: WardrobeSceneView
        let world = WardrobeScene()
        var built: [WardrobeItem] = []
        var light = LightSettings.load()
        weak var view: SCNView?
        private var startX: Float = 0
        private var startDistance: Float = 0
        private var last: CGPoint = .zero
        private var velocityLink: CADisplayLink?
        private var velocity: Float = 0

        init(_ p: WardrobeSceneView) { parent = p }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            guard let v = view else { return }
            // Habit sorti : le doigt le fait tourner. Sinon : on parcourt la penderie.
            if world.selected != nil {
                let t = g.translation(in: v)
                if g.state == .began { last = .zero }
                world.rotateSelected(dx: Float(t.x - last.x) * 0.012, dy: Float(t.y - last.y) * 0.008)
                last = t
                return
            }
            let scale = Float(world.camDistance) / Float(max(1, v.bounds.width)) * 1.1
            switch g.state {
            case .began:
                velocityLink?.invalidate()
                startX = world.camX
            case .changed:
                world.camX = startX - Float(g.translation(in: v).x) * scale
                world.updateCamera(animated: false)
            case .ended, .cancelled:
                velocity = -Float(g.velocity(in: v).x) * scale
                let link = CADisplayLink(target: self, selector: #selector(glide))
                link.add(to: .main, forMode: .common)
                velocityLink = link
            default: break
            }
        }

        @objc private func glide(_ link: CADisplayLink) {
            velocity *= 0.92
            world.camX += velocity * Float(link.duration)
            world.updateCamera(animated: false)
            if abs(velocity) < 0.01 { link.invalidate(); velocityLink = nil }
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            switch g.state {
            case .began: startDistance = world.camDistance
            case .changed:
                world.camDistance = startDistance / Float(g.scale)
                world.updateCamera(animated: false)
            default: break
            }
        }

        @objc func tap(_ g: UITapGestureRecognizer) {
            guard let v = view else { return }
            let hits = v.hitTest(g.location(in: v), options: [.searchMode: SCNHitTestSearchMode.all.rawValue, .ignoreHiddenNodes: true])
            let id = hits.lazy.filter { self.world.isSolid($0) }.compactMap { self.world.id(of: $0.node) }.first
            UISelectionFeedbackGenerator().selectionChanged()
            parent.selected = (id == parent.selected) ? nil : id
        }
    }
}
