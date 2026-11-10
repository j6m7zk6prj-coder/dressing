import SceneKit
import UIKit

// MARK: - La penderie en 3D : caisson en noyer, tringle, cintres, éclairage réaliste

struct WardrobeItem: Equatable {
    let id: UUID
    let category: Category
    let imageFile: String
}

final class WardrobeScene {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let root = SCNNode()
    private(set) var width: Float = 2.4
    private(set) var garmentNodes: [UUID: SCNNode] = [:]
    private var restTransforms: [UUID: (SCNVector3, SCNVector3)] = [:]
    /// Transparence de chaque image (64 × 64), pour ignorer les touches sur le fond retiré.
    private var alphaMaps: [UUID: [UInt8]] = [:]
    private(set) var selected: UUID?

    // Caméra : position le long de la penderie et recul.
    var camX: Float = 0
    var camDistance: Float = 2.7
    let camHeight: Float = 1.25

    static let railY: Float = 1.86
    static let depth: Float = 0.62
    static let railZ: Float = 0.32
    static let height: Float = 2.36

    init() {
        scene.rootNode.addChildNode(root)
        setupEnvironment()
        setupCamera()
    }

    // MARK: Texture

    private static func tex(_ name: String) -> UIImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: nil) { return UIImage(contentsOfFile: url.path) }
        let parts = name.split(separator: ".")
        if parts.count == 2, let url = Bundle.main.url(forResource: String(parts[0]), withExtension: String(parts[1]), subdirectory: "Resources") {
            return UIImage(contentsOfFile: url.path)
        }
        return nil
    }

    private static func pbr(_ albedo: String?, normal: String?, roughness: CGFloat, repeatU: Float = 1, repeatV: Float = 1,
                            color: UIColor? = nil, metalness: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = albedo.flatMap(tex) ?? color ?? UIColor.gray
        if let normal, let n = tex(normal) {
            m.normal.contents = n
            m.normal.intensity = 0.8
        }
        m.roughness.contents = roughness
        m.metalness.contents = metalness
        let t = SCNMatrix4MakeScale(repeatU, repeatV, 1)
        for p in [m.diffuse, m.normal] {
            p.contentsTransform = t
            p.wrapS = .repeat
            p.wrapT = .repeat
            p.mipFilter = .linear
            p.maxAnisotropy = 8
        }
        return m
    }

    // MARK: Pièce et lumières

    private func setupEnvironment() {
        scene.lightingEnvironment.contents = Self.tex("studio_env.jpg")
        scene.lightingEnvironment.intensity = 1.25
        scene.background.contents = UIColor(red: 0.09, green: 0.08, blue: 0.07, alpha: 1)

        // Lumière principale (devant, en hauteur) avec ombres douces.
        let key = SCNLight()
        key.type = .spot
        key.intensity = 950
        key.temperature = 4300
        key.spotInnerAngle = 40
        key.spotOuterAngle = 95
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowSampleCount = 16
        key.shadowRadius = 6
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.shadowColor = UIColor(white: 0, alpha: 0.55)
        key.zNear = 0.3
        key.zFar = 12
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.name = "key"
        keyNode.position = SCNVector3(0.4, 3.1, 2.6)
        keyNode.look(at: SCNVector3(0, 1.1, 0.2))
        scene.rootNode.addChildNode(keyNode)

        // Lumière d'appoint froide, sans ombre.
        let fill = SCNLight()
        fill.type = .omni
        fill.intensity = 180
        fill.temperature = 6500
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.position = SCNVector3(-2.5, 1.6, 3.2)
        scene.rootNode.addChildNode(fillNode)
    }

    private func setupCamera() {
        let cam = SCNCamera()
        cam.fieldOfView = 52
        cam.zNear = 0.05
        cam.zFar = 40
        cam.wantsHDR = true
        cam.wantsExposureAdaptation = false
        cam.exposureOffset = -0.15
        cam.bloomIntensity = 0.25
        cam.bloomThreshold = 0.9
        cam.bloomBlurRadius = 10
        cam.screenSpaceAmbientOcclusionIntensity = 1.1
        cam.screenSpaceAmbientOcclusionRadius = 0.12
        cam.vignettingIntensity = 0.35
        cam.vignettingPower = 0.6
        cam.contrast = 0.06
        cam.saturation = 1.04
        cam.focusDistance = 2.4
        cam.fStop = 2.8
        cam.apertureBladeCount = 6
        cameraNode.camera = cam
        scene.rootNode.addChildNode(cameraNode)
        updateCamera(animated: false)
    }

    func updateCamera(animated: Bool, duration: CFTimeInterval = 0.55) {
        let half = max(0, width / 2 - 0.55)
        camX = min(max(camX, -half), half)
        camDistance = min(max(camDistance, 1.1), 4.2)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? duration : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cameraNode.position = SCNVector3(camX, camHeight + (camDistance - 2.7) * 0.12, Self.railZ + camDistance)
        cameraNode.look(at: SCNVector3(camX, 1.18, 0.2))
        SCNTransaction.commit()
    }

    // MARK: Construction

    func build(_ items: [WardrobeItem]) {
        root.childNodes.forEach { $0.removeFromParentNode() }
        garmentNodes = [:]
        restTransforms = [:]
        alphaMaps = [:]
        selected = nil

        let hanging = items.filter { $0.category.hangs }
            .sorted { order($0.category) < order($1.category) }
        let shoes = items.filter { $0.category == .shoes }
        let accessories = items.filter { $0.category == .accessory }

        let spacing: Float = 0.2
        width = max(2.2, Float(hanging.count) * spacing + 0.7, Float(shoes.count) * 0.4 + 0.5, Float(accessories.count) * 0.34 + 0.5)
        buildRoom()
        buildCarcass()

        // Habits sur la tringle, en éventail.
        let start = -Float(max(0, hanging.count - 1)) * spacing / 2
        for (i, item) in hanging.enumerated() {
            guard let node = garment(item) else { continue }
            let hanger = hangerNode()
            hanger.addChildNode(node)
            hanger.position = SCNVector3(start + Float(i) * spacing, Self.railY, Self.railZ)
            hanger.eulerAngles = SCNVector3(0, -0.98, 0)
            hanger.name = "item:\(item.id.uuidString)"
            root.addChildNode(hanger)
            garmentNodes[item.id] = hanger
            restTransforms[item.id] = (hanger.position, hanger.eulerAngles)
        }

        // Chaussures en bas.
        let sStart = -Float(max(0, shoes.count - 1)) * 0.4 / 2
        for (i, item) in shoes.enumerated() {
            guard let node = standing(item, height: 0.17) else { continue }
            node.position = SCNVector3(sStart + Float(i) * 0.4, 0.105, 0.38)
            node.eulerAngles = SCNVector3(0, i % 2 == 0 ? 0.18 : -0.18, 0)
            node.name = "item:\(item.id.uuidString)"
            root.addChildNode(node)
            garmentNodes[item.id] = node
            restTransforms[item.id] = (node.position, node.eulerAngles)
        }

        // Accessoires sur l'étagère du haut.
        let aStart = -Float(max(0, accessories.count - 1)) * 0.34 / 2
        for (i, item) in accessories.enumerated() {
            guard let node = standing(item, height: 0.17) else { continue }
            node.position = SCNVector3(aStart + Float(i) * 0.34, 2.08, 0.3)
            node.name = "item:\(item.id.uuidString)"
            root.addChildNode(node)
            garmentNodes[item.id] = node
            restTransforms[item.id] = (node.position, node.eulerAngles)
        }
        updateCamera(animated: false)
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
        floor.firstMaterial = Self.pbr("floor_albedo.jpg", normal: "floor_normal.png", roughness: 0.55,
                                       repeatU: (width + 8) / 1.6, repeatV: 10 / 1.6)
        let f = SCNNode(geometry: floor)
        f.eulerAngles.x = -.pi / 2
        f.position = SCNVector3(0, 0, 4)
        root.addChildNode(f)

        let wall = SCNPlane(width: CGFloat(width + 8), height: 4)
        wall.firstMaterial = Self.pbr("wall_albedo.jpg", normal: "wall_normal.png", roughness: 0.9,
                                      repeatU: (width + 8) / 2, repeatV: 2)
        let w = SCNNode(geometry: wall)
        w.position = SCNVector3(0, 2, -0.03)
        root.addChildNode(w)

        // Plinthe.
        let skirting = SCNBox(width: CGFloat(width + 8), height: 0.09, length: 0.015, chamferRadius: 0.003)
        skirting.firstMaterial = Self.pbr(nil, normal: nil, roughness: 0.4, color: UIColor(white: 0.93, alpha: 1))
        let s = SCNNode(geometry: skirting)
        s.position = SCNVector3(0, 0.045, -0.02)
        root.addChildNode(s)
    }

    private func buildCarcass() {
        let wood = { (u: Float, v: Float) in Self.pbr("wood_albedo.jpg", normal: "wood_normal.png", roughness: 0.42, repeatU: u, repeatV: v) }
        let t: CGFloat = 0.025
        let W = CGFloat(width), H = CGFloat(Self.height), D = CGFloat(Self.depth)

        func panel(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ p: SCNVector3, _ u: Float, _ v: Float) {
            let b = SCNBox(width: w, height: h, length: l, chamferRadius: 0.004)
            b.firstMaterial = wood(u, v)
            let n = SCNNode(geometry: b)
            n.position = p
            n.castsShadow = true
            root.addChildNode(n)
        }
        // Fond (un peu plus clair : on le voit beaucoup).
        let back = SCNBox(width: W, height: H, length: 0.012, chamferRadius: 0)
        let backMat = wood(Float(W) / 1.2, Float(H) / 1.2)
        backMat.multiply.contents = UIColor(white: 1.15, alpha: 1)
        back.firstMaterial = backMat
        let backNode = SCNNode(geometry: back)
        backNode.position = SCNVector3(0, Float(H) / 2, 0.006)
        root.addChildNode(backNode)
        // Côtés, dessus, socle, étagères.
        panel(t, H, D, SCNVector3(-Float(W) / 2 - Float(t) / 2, Float(H) / 2, Float(D) / 2), 0.5, Float(H) / 1.2)
        panel(t, H, D, SCNVector3(Float(W) / 2 + Float(t) / 2, Float(H) / 2, Float(D) / 2), 0.5, Float(H) / 1.2)
        panel(W + 2 * t, t, D + 0.02, SCNVector3(0, Float(H) + Float(t) / 2, Float(D) / 2 + 0.01), Float(W) / 1.2, 0.5)
        panel(W, 0.09, D, SCNVector3(0, 0.045, Float(D) / 2), Float(W) / 1.2, 0.2)
        panel(W, t, D - 0.02, SCNVector3(0, 2.0, Float(D) / 2 - 0.01), Float(W) / 1.2, 0.5)

        // Tringle chromée.
        let rail = SCNCylinder(radius: 0.012, height: W - 0.02)
        rail.firstMaterial = Self.pbr(nil, normal: nil, roughness: 0.18, color: UIColor(white: 0.85, alpha: 1), metalness: 1)
        let r = SCNNode(geometry: rail)
        r.eulerAngles.z = .pi / 2
        r.position = SCNVector3(0, Self.railY, Self.railZ)
        root.addChildNode(r)
        for x in [-Float(W) / 2 + 0.03, Float(W) / 2 - 0.03] {
            let cup = SCNCylinder(radius: 0.022, height: 0.012)
            cup.firstMaterial = rail.firstMaterial
            let c = SCNNode(geometry: cup)
            c.eulerAngles.z = .pi / 2
            c.position = SCNVector3(x + (x < 0 ? -0.02 : 0.02), Self.railY, Self.railZ)
            root.addChildNode(c)
        }

        // Bande LED sous l'étagère + lumières chaudes dans la penderie.
        let led = SCNBox(width: W - 0.04, height: 0.006, length: 0.02, chamferRadius: 0.002)
        let ledMat = SCNMaterial()
        ledMat.lightingModel = .constant
        ledMat.diffuse.contents = UIColor(red: 1, green: 0.86, blue: 0.68, alpha: 1)
        ledMat.emission.contents = UIColor(red: 1, green: 0.86, blue: 0.68, alpha: 1)
        ledMat.emission.intensity = 2.5
        led.firstMaterial = ledMat
        let ledNode = SCNNode(geometry: led)
        ledNode.position = SCNVector3(0, 2.0 - Float(t) / 2 - 0.004, Float(D) - 0.06)
        ledNode.castsShadow = false
        root.addChildNode(ledNode)

        let count = max(2, Int((width / 0.9).rounded()))
        for i in 0..<count {
            let x = -width / 2 + (Float(i) + 0.5) * width / Float(count)
            let l = SCNLight()
            l.type = .spot
            l.intensity = 260
            l.temperature = 3200
            l.spotInnerAngle = 60
            l.spotOuterAngle = 120
            l.attenuationStartDistance = 0.2
            l.attenuationEndDistance = 2.6
            l.castsShadow = i == count / 2
            l.shadowMode = .deferred
            l.shadowSampleCount = 8
            l.shadowRadius = 8
            l.shadowColor = UIColor(white: 0, alpha: 0.35)
            let n = SCNNode()
            n.light = l
            n.position = SCNVector3(x, 1.97, Float(D) - 0.08)
            n.eulerAngles.x = -.pi / 2 + 0.25
            root.addChildNode(n)
        }
    }

    // MARK: Habits

    private func garment(_ item: WardrobeItem) -> SCNNode? {
        guard let img = ImageStore.texture(item.imageFile) else { return nil }
        alphaMaps[item.id] = Self.alphaMap(img)
        let w = Float(item.category.realWidth)
        let aspect = Float(img.size.height / max(1, img.size.width))
        let h = w * aspect
        let geo = Self.cloth(width: w, height: h, seed: Float(abs(item.id.hashValue % 1000)) / 100)
        geo.firstMaterial = Self.fabric(img)
        let node = SCNNode(geometry: geo)
        node.position = SCNVector3(0, -0.075, 0)
        node.castsShadow = true
        return node
    }

    private func standing(_ item: WardrobeItem, height: Float) -> SCNNode? {
        guard let img = ImageStore.texture(item.imageFile) else { return nil }
        alphaMaps[item.id] = Self.alphaMap(img)
        let w = Float(item.category.realWidth)
        let aspect = Float(img.size.height / max(1, img.size.width))
        let h = w * aspect
        let geo = Self.cloth(width: w, height: h, seed: 0, bulge: 0.02, wave: 0)
        geo.firstMaterial = Self.fabric(img, roughness: 0.5)
        let node = SCNNode(geometry: geo)
        node.pivot = SCNMatrix4MakeTranslation(0, -h, 0)
        node.castsShadow = true
        return node
    }

    private static let fabricNormal = tex("fabric_normal.png")

    private static func fabric(_ img: UIImage, roughness: CGFloat = 0.88) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = img
        m.diffuse.mipFilter = .linear
        m.normal.contents = fabricNormal
        m.normal.intensity = 0.45
        m.normal.contentsTransform = SCNMatrix4MakeScale(7, 7, 1)
        m.normal.wrapS = .repeat
        m.normal.wrapT = .repeat
        m.roughness.contents = roughness
        m.metalness.contents = 0.0
        m.isDoubleSided = true
        // Le fond transparent de la photo détourée ne s'affiche pas (ni son ombre).
        m.transparencyMode = .aOne
        m.blendMode = .alpha
        m.shaderModifiers = [.surface: "if (_surface.diffuse.a < 0.45) { discard_fragment(); }"]
        return m
    }

    /// Un tissu légèrement bombé avec des plis en bas (au lieu d'un plan tout plat).
    static func cloth(width w: Float, height h: Float, seed: Float, bulge: Float = 0.045, wave: Float = 0.012) -> SCNGeometry {
        let nx = 18, ny = 26
        var verts: [SCNVector3] = [], norms: [SCNVector3] = [], uvs: [CGPoint] = []
        func z(_ u: Float, _ v: Float) -> Float {
            let x = u - 0.5
            let chest = bulge * cos(x * .pi) * (0.55 + 0.45 * sin(v * .pi * 0.9 + 0.2))
            let folds = wave * v * v * sin(x * 22 + seed * 3) + wave * 0.5 * v * sin(x * 9 + seed)
            return chest + folds
        }
        for j in 0...ny {
            for i in 0...nx {
                let u = Float(i) / Float(nx), v = Float(j) / Float(ny)
                let p = SCNVector3((u - 0.5) * w, -v * h, z(u, v))
                let e: Float = 0.01
                let dzdu = (z(u + e, v) - z(u - e, v)) / (2 * e * w)
                let dzdv = (z(u, v + e) - z(u, v - e)) / (2 * e * h)
                let n = SCNVector3(-dzdu, dzdv, 1)
                let l = sqrt(n.x * n.x + n.y * n.y + n.z * n.z)
                verts.append(p)
                norms.append(SCNVector3(n.x / l, n.y / l, n.z / l))
                uvs.append(CGPoint(x: CGFloat(u), y: CGFloat(v)))
            }
        }
        var idx: [Int32] = []
        let row = nx + 1
        for j in 0..<ny {
            for i in 0..<nx {
                let a = Int32(j * row + i), b = a + 1, c = Int32((j + 1) * row + i), d = c + 1
                idx += [a, c, b, b, c, d]
            }
        }
        let el = SCNGeometryElement(indices: idx, primitiveType: .triangles)
        return SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms),
                                     SCNGeometrySource(textureCoordinates: uvs)], elements: [el])
    }

    /// Cintre en bois avec crochet chromé.
    private func hangerNode() -> SCNNode {
        let n = SCNNode()
        let woodMat = Self.pbr(nil, normal: nil, roughness: 0.35, color: UIColor(red: 0.55, green: 0.38, blue: 0.24, alpha: 1))
        for side: Float in [-1, 1] {
            let arm = SCNCapsule(capRadius: 0.011, height: 0.25)
            arm.firstMaterial = woodMat
            let a = SCNNode(geometry: arm)
            a.eulerAngles.z = side * (.pi / 2 - 0.3)
            a.position = SCNVector3(side * 0.115, -0.07, 0.004)
            n.addChildNode(a)
        }
        let metal = Self.pbr(nil, normal: nil, roughness: 0.2, color: UIColor(white: 0.8, alpha: 1), metalness: 1)
        let neck = SCNCylinder(radius: 0.003, height: 0.05)
        neck.firstMaterial = metal
        let neckNode = SCNNode(geometry: neck)
        neckNode.position = SCNVector3(0, -0.03, 0)
        n.addChildNode(neckNode)
        let hook = SCNTorus(ringRadius: 0.019, pipeRadius: 0.003)
        hook.firstMaterial = metal
        let hookNode = SCNNode(geometry: hook)
        hookNode.eulerAngles.z = .pi / 2
        hookNode.position = SCNVector3(0, 0.0, 0)
        n.addChildNode(hookNode)
        return n
    }

    // MARK: Sélection

    private static func alphaMap(_ img: UIImage) -> [UInt8] {
        let n = 64
        var data = [UInt8](repeating: 0, count: n * n)
        guard let cg = img.cgImage else { return [UInt8](repeating: 255, count: n * n) }
        data.withUnsafeMutableBytes { buf in
            if let ctx = CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n,
                                   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) {
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
            }
        }
        return data
    }

    /// Vrai si la touche tombe sur le tissu (et pas sur le fond transparent).
    func isSolid(_ hit: SCNHitTestResult) -> Bool {
        guard let id = id(of: hit.node), let map = alphaMaps[id], hit.node.geometry != nil else { return true }
        let uv = hit.textureCoordinates(withMappingChannel: 0)
        let n = 64
        let x = min(n - 1, max(0, Int(uv.x * CGFloat(n))))
        let y = min(n - 1, max(0, Int((1 - uv.y) * CGFloat(n))))
        return map[(n - 1 - y) * n + x] > 110
    }

    func id(of node: SCNNode) -> UUID? {
        var n: SCNNode? = node
        while let cur = n {
            if let name = cur.name, name.hasPrefix("item:") { return UUID(uuidString: String(name.dropFirst(5))) }
            n = cur.parent
        }
        return nil
    }

    func select(_ id: UUID?) {
        if let old = selected, let node = garmentNodes[old], let rest = restTransforms[old] {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.5
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            node.position = rest.0
            node.eulerAngles = rest.1
            SCNTransaction.commit()
        }
        selected = id
        guard let id, let node = garmentNodes[id], let rest = restTransforms[id] else {
            cameraNode.camera?.wantsDepthOfField = false
            camDistance = 2.7
            updateCamera(animated: true)
            return
        }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.55
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        node.position = SCNVector3(rest.0.x, rest.0.y, rest.0.z + (rest.0.y > 1.5 ? 0.42 : 0.3))
        node.eulerAngles = SCNVector3(0, 0, 0)
        SCNTransaction.commit()
        camX = rest.0.x
        camDistance = rest.0.y > 1.5 ? 1.55 : 1.25
        cameraNode.camera?.wantsDepthOfField = true
        cameraNode.camera?.focusDistance = CGFloat(camDistance - 0.42)
        updateCamera(animated: true)
    }

    /// Recentre la caméra sur un habit (après « Voir dans la penderie »).
    func focus(_ id: UUID) { select(id) }
}
