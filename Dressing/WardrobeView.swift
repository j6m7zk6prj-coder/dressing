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

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.09, green: 0.08, blue: 0.07).ignoresSafeArea()
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
                    WardrobeSceneView(items: items, selected: $selected)
                        .ignoresSafeArea()
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let id = selected, let g = garments.first(where: { $0.id == id }) {
                    SelectedCard(garment: g, onOpen: { detail = g }, onClose: { selected = nil })
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Ajouter un habit")
                }
            }
            .sheet(isPresented: $adding) { AddGarmentView() }
            .sheet(item: $detail) { g in
                NavigationStack { GarmentDetailView(garment: g, onShowInWardrobe: nil) }
            }
            .onChange(of: focusID) { _, id in
                if let id { filter = nil; selected = id; focusID = nil }
            }
            .onAppear {
                if Demo.state == "selected" { selected = garments.first(where: { $0.category == .jersey })?.id }
            }
        }
    }

    private var items: [WardrobeItem] {
        garments.filter { filter == nil || $0.category == filter }
            .map { WardrobeItem(id: $0.id, category: $0.category, imageFile: $0.imageFile) }
    }
}

/// La fiche résumée de l'habit sorti de la penderie.
struct SelectedCard: View {
    let garment: Garment
    var onOpen: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(garment.title).font(.headline).lineLimit(1)
                Text(garment.subtitle.isEmpty ? garment.category.singular : garment.subtitle)
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if let v = garment.value ?? garment.purchasePrice {
                    Text(Money.format(v)).font(.subheadline.weight(.semibold).monospacedDigit())
                }
            }
            Spacer(minLength: 0)
            Button("Fiche", action: onOpen).secondaryButton()
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .secondaryButton()
            .accessibilityLabel("Remettre sur la tringle")
        }
        .padding(16)
        .glassPanel(cornerRadius: 26)
    }
}

// MARK: - La vue SceneKit et les gestes

struct WardrobeSceneView: UIViewRepresentable {
    let items: [WardrobeItem]
    @Binding var selected: UUID?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = context.coordinator.world.scene
        v.pointOfView = context.coordinator.world.cameraNode
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 60
        v.backgroundColor = UIColor(red: 0.09, green: 0.08, blue: 0.07, alpha: 1)
        v.rendersContinuously = false
        v.isJitteringEnabled = true
        let c = context.coordinator
        v.addGestureRecognizer(UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan(_:))))
        v.addGestureRecognizer(UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.pinch(_:))))
        v.addGestureRecognizer(UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:))))
        c.view = v
        c.world.build(items)
        c.built = items
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
        if c.world.selected != selected { c.world.select(selected) }
    }

    final class Coordinator: NSObject {
        var parent: WardrobeSceneView
        let world = WardrobeScene()
        var built: [WardrobeItem] = []
        weak var view: SCNView?
        private var startX: Float = 0
        private var startDistance: Float = 0
        private var velocityLink: CADisplayLink?
        private var velocity: Float = 0

        init(_ p: WardrobeSceneView) { parent = p }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            guard let v = view else { return }
            let scale = Float(world.camDistance) / Float(max(1, v.bounds.width)) * 1.1
            switch g.state {
            case .began:
                velocityLink?.invalidate()
                startX = world.camX
                if parent.selected != nil { parent.selected = nil }
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
