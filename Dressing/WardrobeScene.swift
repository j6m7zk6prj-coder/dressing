import SceneKit
import UIKit

// MARK: - Réglages de lumière (choisis par l'utilisateur)

struct LightSettings: Codable, Equatable {
    /// 0,2 … 2 (1 = normal).
    var intensity: Double = 0.75
    /// Température des spots, en kelvins.
    var temperature: Double = 4200
    var ledOn = true
    var ledColor: [Double] = [1, 0.86, 0.70]
    /// Exposition de la caméra (-2 … +1).
    var exposure: Double = -0.35
    /// Lumière de la pièce autour (0 … 1,5).
    var ambient: Double = 0.7

    static let key = "lightSettings"

    static func load() -> LightSettings {
        guard let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode(LightSettings.self, from: d) else { return LightSettings() }
        return s
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key) }
    }

    var led: UIColor { UIColor(red: ledColor[0], green: ledColor[1], blue: ledColor[2], alpha: 1) }

    static let presets: [(String, LightSettings)] = [
        ("Boutique", LightSettings(intensity: 0.9, temperature: 4300, ledOn: true, ledColor: [1, 0.88, 0.74], exposure: -0.3, ambient: 0.8)),
        ("Soirée", LightSettings(intensity: 0.45, temperature: 2900, ledOn: true, ledColor: [1, 0.72, 0.45], exposure: -0.5, ambient: 0.35)),
        ("Lumière du jour", LightSettings(intensity: 1.0, temperature: 5800, ledOn: false, ledColor: [1, 1, 1], exposure: -0.2, ambient: 1.2)),
        ("Vestiaire", LightSettings(intensity: 0.8, temperature: 6200, ledOn: true, ledColor: [0.75, 0.85, 1], exposure: -0.35, ambient: 0.6)),
        ("Néon", LightSettings(intensity: 0.55, temperature: 5000, ledOn: true, ledColor: [0.95, 0.25, 0.9], exposure: -0.4, ambient: 0.3)),
    ]
}

// MARK: - Ce qu'il faut pour afficher un habit en 3D

struct WardrobeItem: Equatable {
    let id: UUID
    let category: Category
    let files: [PhotoView: String]
    let size: String
}

/// Fabrique (et garde en mémoire) le modèle 3D de chaque habit.
enum ModelFactory {
    private static var cache: [String: SCNNode] = [:]
    private static let lock = NSLock()

    /// Construit le modèle en arrière-plan puis le rend sur le fil principal.
    static func load(_ item: WardrobeItem, completion: @escaping (SCNNode?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let n = node(for: item)
            DispatchQueue.main.async { completion(n) }
        }
    }

    static func node(for item: WardrobeItem) -> SCNNode? {
        let key = item.id.uuidString + item.files.values.sorted().joined()
        lock.lock()
        let cached = cache[key]
        lock.unlock()
        if let n = cached { return n.clone() }
        var made: SCNNode?
        let main = item.category.mainView
        guard let mainFile = item.files[main], let mainImg = ImageStore.texture(mainFile) else { return nil }
        switch item.category {
        case .shoes:
            var views: [PhotoView: UIImage] = [:]
            for (v, f) in item.files { views[v] = ImageStore.texture(f) }
            made = ShoeMesh.make(views: views, length: ShoeMesh.length(forSize: item.size))
            if made == nil { made = flat(mainImg, width: 0.3) }
        default:
            let back = item.files[.back].flatMap(ImageStore.texture)
            let seed = Float(abs(item.id.hashValue % 1000)) / 100
            let depth: Float = item.category == .accessory ? 0.03 : (item.category == .pants ? 0.035 : 0.05)
            made = ClothMesh.make(front: mainImg, back: back, width: Float(item.category.realWidth), seed: seed, depth: depth,
                                  folds: item.category == .accessory ? 0 : 0.012)
        }
        guard let n = made else { return nil }
        lock.lock(); cache[key] = n; lock.unlock()
        return n.clone()
    }

    private static func flat(_ img: UIImage, width: Float) -> SCNNode {
        let n = ClothMesh.make(front: img, back: nil, width: width, seed: 0, depth: 0.04, folds: 0)
        let h = width * Float(img.size.height / max(1, img.size.width))
        n.pivot = SCNMatrix4MakeTranslation(0, -h, 0)
        return n
    }

    static func clear() { lock.lock(); cache = [:]; lock.unlock() }
}

// MARK: - La penderie en 3D

final class WardrobeScene {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let root = SCNNode()
    private var lights: (key: SCNLight, fill: SCNLight, inside: [SCNLight], led: SCNMaterial?)
    private(set) var width: Float = 2.4
    /// Pour chaque habit : le nœud posé (déplacé à la sélection) et son « pivot de rotation » (manipulé au doigt).
    private(set) var holders: [UUID: SCNNode] = [:]
    private var spinners: [UUID: SCNNode] = [:]
    private var rest: [UUID: (SCNVector3, SCNVector3)] = [:]
    private var alphaMaps: [UUID: AlphaMap] = [:]
    private var categories: [UUID: Category] = [:]
    /// Taille réelle de chaque habit (hauteur, largeur), connue avant même que le modèle 3D soit prêt.
    private var extents: [UUID: (h: Float, w: Float)] = [:]
    private(set) var selected: UUID?
    /// Largeur / hauteur de l'écran (pour cadrer en mode portrait).
    var viewAspect: Float = 0.46

    var camX: Float = 0
    var camDistance: Float = 2.7
    var lookY: Float = 1.2

    static let railY: Float = 1.86
    static let depth: Float = 0.62
    static let railZ: Float = 0.32
    static let height: Float = 2.36
    static let drawerTop: Float = 0.62
    static let shelfY: Float = 2.0

    init() {
        lights = (SCNLight(), SCNLight(), [], nil)
        scene.rootNode.addChildNode(root)
        setupCamera()
        apply(LightSettings.load())
    }

    // MARK: Caméra et lumière

    private func setupCamera() {
        let cam = SCNCamera()
        cam.fieldOfView = 52
        cam.zNear = 0.03
        cam.zFar = 40
        cam.wantsHDR = true
        cam.wantsExposureAdaptation = false
        cam.bloomIntensity = 0
        cam.screenSpaceAmbientOcclusionIntensity = 0.9
        cam.screenSpaceAmbientOcclusionRadius = 0.1
        cam.vignettingIntensity = 0.3
        cam.vignettingPower = 0.6
        cam.saturation = 1.02
        cam.focusDistance = 2.4
        cam.fStop = 2.8
        cameraNode.camera = cam
        scene.rootNode.addChildNode(cameraNode)
        updateCamera(animated: false)
    }

    func updateCamera(animated: Bool, duration: CFTimeInterval = 0.55) {
        let half = max(0, width / 2 - 0.5)
        camX = min(max(camX, -half), half)
        camDistance = min(max(camDistance, 0.7), 4.2)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? duration : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cameraNode.position = SCNVector3(camX, lookY + 0.08 + (camDistance - 2.7) * 0.08, Self.railZ + camDistance)
        cameraNode.look(at: SCNVector3(camX, lookY, 0.2))
        SCNTransaction.commit()
    }

    /// Applique les réglages de lumière choisis.
    func apply(_ s: LightSettings) {
        let k = CGFloat(s.intensity)
        scene.lightingEnvironment.contents = Materials.tex("studio_env.jpg")
        scene.lightingEnvironment.intensity = CGFloat(s.ambient) * 0.75
        scene.background.contents = UIColor(red: 0.07, green: 0.065, blue: 0.06, alpha: 1)
        lights.key.intensity = 420 * k
        lights.key.temperature = CGFloat(s.temperature)
        lights.fill.intensity = 70 * CGFloat(s.ambient)
        for l in lights.inside {
            l.intensity = 70 * k * (s.ledOn ? 1 : 0.35)
            l.temperature = CGFloat(s.temperature)
            l.color = s.ledOn ? s.led : UIColor.white
        }
        if let m = lights.led {
            m.emission.contents = s.ledOn ? s.led : UIColor.black
            m.diffuse.contents = s.ledOn ? s.led : UIColor(white: 0.85, alpha: 1)
            m.emission.intensity = 0.9
        }
        cameraNode.camera?.exposureOffset = CGFloat(s.exposure)
    }

    private func setupLights() {
        let key = SCNLight()
        key.type = .spot
        key.spotInnerAngle = 40
        key.spotOuterAngle = 100
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowSampleCount = 16
        key.shadowRadius = 5
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.shadowColor = UIColor(white: 0, alpha: 0.5)
        key.zNear = 0.3
        key.zFar = 12
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(0.5, 3.1, 2.7)
        keyNode.look(at: SCNVector3(0, 1.1, 0.2))
        root.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .omni
        fill.temperature = 6500
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.position = SCNVector3(-2.5, 1.6, 3.2)
        root.addChildNode(fillNode)
        lights.key = key
        lights.fill = fill
    }

    // MARK: Construction

    private var generation = 0

    func build(_ items: [WardrobeItem]) {
        generation += 1
        let gen = generation
        root.childNodes.forEach { $0.removeFromParentNode() }
        holders = [:]; spinners = [:]; rest = [:]; alphaMaps = [:]; categories = [:]; extents = [:]
        selected = nil
        lights.inside = []

        let hanging = items.filter { $0.category.hangs }.sorted { order($0.category) < order($1.category) }
        let shoes = items.filter { $0.category == .shoes }
        let accessories = items.filter { $0.category == .accessory }

        let spacing: Float = 0.2
        width = max(2.2, Float(hanging.count) * spacing + 0.7, Float(shoes.count) * 0.36 + 0.5, Float(accessories.count) * 0.34 + 0.5)
        setupLights()
        buildRoom()
        buildCarcass()

        // Habits sur la tringle, sur leur cintre, en éventail.
        let start = -Float(max(0, hanging.count - 1)) * spacing / 2
        for (i, item) in hanging.enumerated() {
            let holder = SCNNode()
            let spin = SCNNode()
            let hanger = HangerModel.make(width: item.category == .pants ? 0.38 : 0.43)
            spin.addChildNode(hanger)
            ModelFactory.load(item) { [weak self] cloth in
                guard let self, gen == self.generation, let cloth else { return }
                cloth.position = SCNVector3(0, -0.052, 0)
                cloth.opacity = 0
                spin.addChildNode(cloth)
                cloth.runAction(.fadeIn(duration: 0.25))
            }
            holder.addChildNode(spin)
            holder.position = SCNVector3(start + Float(i) * spacing, Self.railY, Self.railZ)
            holder.eulerAngles = SCNVector3(0, -0.98, 0)
            register(item, holder: holder, spin: spin)
        }

        // Chaussures en 3D, posées sur la commode.
        let sStart = -Float(max(0, shoes.count - 1)) * 0.36 / 2
        for (i, item) in shoes.enumerated() {
            let holder = SCNNode(), spin = SCNNode()
            ModelFactory.load(item) { [weak self] shoe in
                guard let self, gen == self.generation, let shoe else { return }
                shoe.opacity = 0
                spin.addChildNode(shoe)
                shoe.runAction(.fadeIn(duration: 0.3))
            }
            holder.addChildNode(spin)
            holder.position = SCNVector3(sStart + Float(i) * 0.36, Self.drawerTop, 0.34)
            holder.eulerAngles = SCNVector3(0, i % 2 == 0 ? 0.5 : -0.5, 0)
            register(item, holder: holder, spin: spin)
        }

        // Accessoires sur l'étagère du haut.
        let aStart = -Float(max(0, accessories.count - 1)) * 0.34 / 2
        for (i, item) in accessories.enumerated() {
            let holder = SCNNode(), spin = SCNNode()
            ModelFactory.load(item) { [weak self] acc in
                guard let self, gen == self.generation, let acc else { return }
                let (minB, _) = acc.boundingBox
                acc.position = SCNVector3(0, -minB.y, 0)
                acc.opacity = 0
                spin.addChildNode(acc)
                acc.runAction(.fadeIn(duration: 0.25))
            }
            holder.addChildNode(spin)
            holder.position = SCNVector3(aStart + Float(i) * 0.34, Self.shelfY + 0.0125, 0.3)
            register(item, holder: holder, spin: spin)
        }
        apply(LightSettings.load())
        updateCamera(animated: false)
    }

    private func register(_ item: WardrobeItem, holder: SCNNode, spin: SCNNode) {
        holder.name = "item:\(item.id.uuidString)"
        root.addChildNode(holder)
        holders[item.id] = holder
        spinners[item.id] = spin
        rest[item.id] = (holder.position, holder.eulerAngles)
        categories[item.id] = item.category
        if let f = item.files[item.category.mainView], let img = ImageStore.texture(f) {
            alphaMaps[item.id] = AlphaMap(img, maxSide: 64)
            let aspect = Float(img.size.height / max(1, img.size.width))
            let w = item.category == .shoes ? ShoeMesh.length(forSize: item.size) : Float(item.category.realWidth)
            extents[item.id] = (w * aspect, w)
        }
    }

    private func order(_ c: Category) -> Int {
        switch c {
        case .jersey: return 0
        case .top: return 1
        case .jacket: return 2
        default: return 3
        }
    }

    private func buildRoom() {
        let floor = SCNPlane(width: CGFloat(width + 8), height: 10)
        let fm = SCNMaterial()
        fm.lightingModel = .physicallyBased
        fm.diffuse.contents = Materials.tex("floor_albedo.jpg")
        fm.normal.contents = Materials.tex("floor_normal.png")
        fm.roughness.contents = 0.55
        for p in [fm.diffuse, fm.normal] {
            p.contentsTransform = SCNMatrix4MakeScale((width + 8) / 1.6, 10 / 1.6, 1)
            p.wrapS = .repeat; p.wrapT = .repeat; p.mipFilter = .linear; p.maxAnisotropy = 8
        }
        floor.firstMaterial = fm
        let f = SCNNode(geometry: floor)
        f.eulerAngles.x = -.pi / 2
        f.position = SCNVector3(0, 0, 4)
        root.addChildNode(f)

        let wall = SCNPlane(width: CGFloat(width + 8), height: 4)
        let wm = SCNMaterial()
        wm.lightingModel = .physicallyBased
        wm.diffuse.contents = Materials.tex("wall_albedo.jpg")
        wm.normal.contents = Materials.tex("wall_normal.png")
        wm.roughness.contents = 0.92
        for p in [wm.diffuse, wm.normal] {
            p.contentsTransform = SCNMatrix4MakeScale((width + 8) / 2, 2, 1)
            p.wrapS = .repeat; p.wrapT = .repeat
        }
        wall.firstMaterial = wm
        let w = SCNNode(geometry: wall)
        w.position = SCNVector3(0, 2, -0.03)
        root.addChildNode(w)

        let skirting = SCNBox(width: CGFloat(width + 8), height: 0.09, length: 0.015, chamferRadius: 0.003)
        skirting.firstMaterial = Materials.plain(UIColor(white: 0.93, alpha: 1), roughness: 0.4)
        let s = SCNNode(geometry: skirting)
        s.position = SCNVector3(0, 0.045, -0.02)
        root.addChildNode(s)
    }

    private func buildCarcass() {
        let walnut = UIColor(white: 1, alpha: 1)
        let t: CGFloat = 0.022
        let W = CGFloat(width), H = CGFloat(Self.height), D = CGFloat(Self.depth)

        func panel(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ p: SCNVector3, _ u: Float, _ v: Float, chamfer: CGFloat = 0.002) {
            let b = SCNBox(width: w, height: h, length: l, chamferRadius: chamfer)
            b.firstMaterial = Materials.wood(walnut, repeatU: u, repeatV: v)
            let n = SCNNode(geometry: b)
            n.position = p
            n.castsShadow = true
            root.addChildNode(n)
        }
        // Fond, côtés, dessus, socle, étagère haute.
        panel(W, H, 0.012, SCNVector3(0, Float(H) / 2, 0.006), Float(W) / 1.2, Float(H) / 1.2, chamfer: 0)
        panel(t, H, D, SCNVector3(-Float(W) / 2 - Float(t) / 2, Float(H) / 2, Float(D) / 2), 0.5, Float(H) / 1.2)
        panel(t, H, D, SCNVector3(Float(W) / 2 + Float(t) / 2, Float(H) / 2, Float(D) / 2), 0.5, Float(H) / 1.2)
        panel(W + 2 * t, t, D + 0.02, SCNVector3(0, Float(H) + Float(t) / 2, Float(D) / 2 + 0.01), Float(W) / 1.2, 0.5)
        panel(W, 0.09, D, SCNVector3(0, 0.045, Float(D) / 2), Float(W) / 1.2, 0.2)
        panel(W, t, D - 0.02, SCNVector3(0, Self.shelfY, Float(D) / 2 - 0.01), Float(W) / 1.2, 0.5)

        // Commode : dessus, deux tiroirs avec un jour de 3 mm et des poignées en métal brossé.
        panel(W, t, D, SCNVector3(0, Self.drawerTop - Float(t) / 2, Float(D) / 2), Float(W) / 1.2, 0.5)
        let drawerH = (Self.drawerTop - Float(t) - 0.09) / 2
        let brushed = Materials.plain(UIColor(white: 0.72, alpha: 1), roughness: 0.32, metalness: 1)
        for k in 0..<2 {
            let y = 0.09 + drawerH * (Float(k) + 0.5)
            let front = SCNBox(width: W - 0.006, height: CGFloat(drawerH - 0.003), length: 0.019, chamferRadius: 0.0025)
            front.firstMaterial = Materials.wood(walnut, repeatU: Float(W) / 1.2, repeatV: 0.4)
            let f = SCNNode(geometry: front)
            f.position = SCNVector3(0, y, Float(D) + 0.0095)
            f.castsShadow = true
            root.addChildNode(f)
            let count = width > 1.6 ? 2 : 1
            for h in 0..<count {
                let hx: Float = count == 1 ? 0 : (h == 0 ? -width / 4 : width / 4)
                let bar = SCNCapsule(capRadius: 0.0065, height: 0.192)
                bar.firstMaterial = brushed
                let b = SCNNode(geometry: bar)
                b.eulerAngles.z = .pi / 2
                b.position = SCNVector3(hx, y, Float(D) + 0.044)
                root.addChildNode(b)
                for dx: Float in [-0.08, 0.08] {
                    let post = SCNCylinder(radius: 0.004, height: 0.026)
                    post.firstMaterial = brushed
                    let pn = SCNNode(geometry: post)
                    pn.eulerAngles.x = .pi / 2
                    pn.position = SCNVector3(hx + dx, y, Float(D) + 0.031)
                    root.addChildNode(pn)
                }
            }
        }

        // Tringle chromée (Ø 24 mm) et ses supports.
        let rail = SCNCylinder(radius: 0.012, height: W - 0.004)
        rail.firstMaterial = Materials.chrome
        let r = SCNNode(geometry: rail)
        r.eulerAngles.z = .pi / 2
        r.position = SCNVector3(0, Self.railY, Self.railZ)
        r.castsShadow = true
        root.addChildNode(r)
        for x in [-Float(W) / 2, Float(W) / 2] {
            let cup = SCNTube(innerRadius: 0.012, outerRadius: 0.02, height: 0.016)
            cup.firstMaterial = Materials.chrome
            let c = SCNNode(geometry: cup)
            c.eulerAngles.z = .pi / 2
            c.position = SCNVector3(x + (x < 0 ? 0.008 : -0.008), Self.railY, Self.railZ)
            root.addChildNode(c)
        }

        // Bande LED encastrée sous l'étagère + spots intérieurs.
        let led = SCNBox(width: W - 0.04, height: 0.005, length: 0.016, chamferRadius: 0.002)
        let ledMat = SCNMaterial()
        ledMat.lightingModel = .constant
        led.firstMaterial = ledMat
        let ledNode = SCNNode(geometry: led)
        ledNode.position = SCNVector3(0, Self.shelfY - Float(t) / 2 - 0.003, Float(D) - 0.05)
        ledNode.castsShadow = false
        root.addChildNode(ledNode)
        lights.led = ledMat

        let count = max(2, Int((width / 0.9).rounded()))
        for i in 0..<count {
            let x = -width / 2 + (Float(i) + 0.5) * width / Float(count)
            let l = SCNLight()
            l.type = .spot
            l.spotInnerAngle = 60
            l.spotOuterAngle = 125
            l.attenuationStartDistance = 0.2
            l.attenuationEndDistance = 2.6
            l.castsShadow = i == count / 2
            l.shadowMode = .deferred
            l.shadowSampleCount = 8
            l.shadowRadius = 8
            l.shadowColor = UIColor(white: 0, alpha: 0.3)
            let n = SCNNode()
            n.light = l
            n.position = SCNVector3(x, Self.shelfY - 0.03, Float(D) - 0.07)
            n.eulerAngles.x = -.pi / 2 + 0.25
            root.addChildNode(n)
            lights.inside.append(l)
        }
    }

    // MARK: Sélection, animations, manipulation

    func id(of node: SCNNode) -> UUID? {
        var n: SCNNode? = node
        while let cur = n {
            if let name = cur.name, name.hasPrefix("item:") { return UUID(uuidString: String(name.dropFirst(5))) }
            n = cur.parent
        }
        return nil
    }

    /// Vrai si la touche tombe sur l'habit (et pas sur le fond transparent de la photo).
    func isSolid(_ hit: SCNHitTestResult) -> Bool {
        guard let id = id(of: hit.node), categories[id] != .shoes, let map = alphaMaps[id],
              hit.node.geometry?.firstMaterial?.diffuse.contents is UIImage else { return true }
        let uv = hit.textureCoordinates(withMappingChannel: 0)
        return map.sample(Float(uv.x), Float(uv.y)) > 0.45
    }

    func select(_ id: UUID?) {
        if let old = selected, old != id { putBack(old) }
        selected = id
        guard let id, let holder = holders[id], let r = rest[id] else {
            cameraNode.camera?.wantsDepthOfField = false
            camDistance = 2.7
            lookY = 1.2
            updateCamera(animated: true)
            return
        }
        let hangs = categories[id]?.hangs ?? false
        let forward: Float = hangs ? 0.46 : 0.32
        let target = SCNVector3(r.0.x, r.0.y + (hangs ? 0.03 : 0.04), r.0.z + forward)
        holder.removeAllActions()
        // 1. Soulève le cintre de la tringle, 2. le sort vers toi en le tournant, 3. il se balance puis se stabilise.
        let lift = SCNAction.move(by: SCNVector3(0, hangs ? 0.045 : 0.03, 0), duration: 0.18)
        lift.timingMode = .easeOut
        let out = SCNAction.group([SCNAction.move(to: target, duration: 0.55),
                                   SCNAction.rotateTo(x: 0, y: hangs ? 0 : CGFloat(-0.35), z: 0, duration: 0.55, usesShortestUnitArc: true)])
        out.timingMode = .easeInEaseOut
        holder.runAction(.sequence([lift, out, hangs ? swing(0.07, y: 0) : .wait(duration: 0)]))

        // Cadre l'habit en entier (hauteur et largeur), en tenant compte de l'écran en portrait.
        let ext = extents[id] ?? (hangs ? (0.75, 0.56) : (0.12, 0.3))
        let fov = Float((cameraNode.camera?.fieldOfView ?? 52) * .pi / 180)
        let tanV = tan(fov / 2)
        let h = ext.h + (hangs ? 0.07 : 0)
        let w = categories[id] == .shoes ? ext.w * 0.95 : ext.w
        let needH = h * 1.3 / (2 * tanV)
        let needW = w * 1.18 / (2 * tanV * max(0.3, viewAspect))
        lookY = hangs ? target.y - 0.052 - ext.h / 2 + 0.02 : target.y + h / 2
        camX = r.0.x
        camDistance = forward + max(needH, needW)
        cameraNode.camera?.wantsDepthOfField = true
        cameraNode.camera?.focusDistance = CGFloat(camDistance - forward)
        updateCamera(animated: true, duration: 0.75)
    }

    private func putBack(_ id: UUID) {
        guard let holder = holders[id], let r = rest[id] else { return }
        let hangs = categories[id]?.hangs ?? false
        spinners[id]?.runAction(SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.35, usesShortestUnitArc: true))
        holder.removeAllActions()
        let above = SCNVector3(r.0.x, r.0.y + (hangs ? 0.045 : 0.03), r.0.z)
        let back = SCNAction.group([SCNAction.move(to: above, duration: 0.5),
                                    SCNAction.rotateTo(x: CGFloat(r.1.x), y: CGFloat(r.1.y), z: CGFloat(r.1.z), duration: 0.5, usesShortestUnitArc: true)])
        back.timingMode = .easeInEaseOut
        let drop = SCNAction.move(to: r.0, duration: 0.16)
        drop.timingMode = .easeIn
        holder.runAction(.sequence([back, drop, hangs ? swing(0.035, y: CGFloat(r.1.y)) : .wait(duration: 0)]))
    }

    /// Balancement amorti autour du crochet (le pivot est sur la tringle).
    private func swing(_ amplitude: CGFloat, y: CGFloat) -> SCNAction {
        var steps: [SCNAction] = []
        var a = amplitude
        var sign: CGFloat = 1
        for _ in 0..<6 {
            let s = SCNAction.rotateTo(x: 0, y: y, z: a * sign, duration: 0.42, usesShortestUnitArc: true)
            s.timingMode = .easeInEaseOut
            steps.append(s)
            a *= 0.55
            sign *= -1
        }
        let end = SCNAction.rotateTo(x: 0, y: y, z: 0, duration: 0.3, usesShortestUnitArc: true)
        end.timingMode = .easeInEaseOut
        steps.append(end)
        return SCNAction.sequence(steps)
    }

    /// Rotation au doigt de l'habit sorti (autour de lui-même).
    func rotateSelected(dx: Float, dy: Float) {
        guard let id = selected, let spin = spinners[id] else { return }
        spin.eulerAngles.y += dx
        if categories[id] == .shoes || categories[id] == .accessory {
            spin.eulerAngles.x = max(-0.9, min(0.9, spin.eulerAngles.x + dy))
        }
    }
}
