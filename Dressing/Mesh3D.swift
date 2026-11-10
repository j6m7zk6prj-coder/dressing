import SceneKit
import UIKit

// MARK: - Transparence d'une image (pour sculpter les volumes et ignorer le fond)

struct AlphaMap {
    let width: Int, height: Int
    let data: [UInt8]

    init?(_ image: UIImage, maxSide: Int = 256) {
        guard let cg = image.cgImage else { return nil }
        let scale = Double(maxSide) / Double(max(cg.width, cg.height))
        let w = max(2, Int(Double(cg.width) * min(1, scale))), h = max(2, Int(Double(cg.height) * min(1, scale)))
        var d = [UInt8](repeating: 0, count: w * h)
        let ok = d.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        width = w; height = h; data = d
    }

    /// u, v entre 0 et 1, v = 0 en haut de l'image. Renvoie l'opacité (0…1), interpolée.
    func sample(_ u: Float, _ v: Float) -> Float {
        let x = u * Float(width - 1), y = v * Float(height - 1)
        guard x >= 0, y >= 0, x <= Float(width - 1), y <= Float(height - 1) else { return 0 }
        let x0 = Int(x), y0 = Int(y), x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
        let fx = x - Float(x0), fy = y - Float(y0)
        func a(_ xx: Int, _ yy: Int) -> Float { Float(data[yy * width + xx]) / 255 }
        return (a(x0, y0) * (1 - fx) + a(x1, y0) * fx) * (1 - fy) + (a(x0, y1) * (1 - fx) + a(x1, y1) * fx) * fy
    }
}

extension UIImage {
    /// Couleur moyenne d'une bande horizontale (v0…v1, 0 = haut), en ignorant le transparent.
    func averageColor(v0: CGFloat, v1: CGFloat) -> UIColor {
        guard let cg = cgImage else { return .darkGray }
        let w = 32, h = 32
        var px = [UInt8](repeating: 0, count: w * h * 4)
        px.withUnsafeMutableBytes { buf in
            if let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        }
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for y in Int(v0 * CGFloat(h))..<max(Int(v0 * CGFloat(h)) + 1, Int(v1 * CGFloat(h))) {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let a = Double(px[i + 3])
                guard a > 200 else { continue }
                r += Double(px[i]); g += Double(px[i + 1]); b += Double(px[i + 2]); n += 255
            }
        }
        guard n > 0 else { return .darkGray }
        return UIColor(red: r / n, green: g / n, blue: b / n, alpha: 1)
    }
}

// MARK: - Matériaux

enum Materials {
    static func tex(_ name: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: nil) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    static let fabricNormal = tex("fabric_normal.png")

    /// Tissu : la photo détourée, avec une fine maille en relief ; le fond transparent est ignoré.
    static func fabric(_ img: UIImage, roughness: CGFloat = 0.86, weave: CGFloat = 0.4) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = img
        m.diffuse.mipFilter = .linear
        m.diffuse.wrapS = .clampToBorder
        m.diffuse.wrapT = .clampToBorder
        m.normal.contents = fabricNormal
        m.normal.intensity = weave
        m.normal.contentsTransform = SCNMatrix4MakeScale(9, 9, 1)
        m.normal.wrapS = .repeat
        m.normal.wrapT = .repeat
        m.roughness.contents = roughness
        m.metalness.contents = 0.0
        m.isDoubleSided = false
        m.transparencyMode = .aOne
        m.blendMode = .alpha
        m.shaderModifiers = [.surface: "if (_surface.diffuse.a < 0.5) { discard_fragment(); }"]
        return m
    }

    static func plain(_ color: UIColor, roughness: CGFloat, metalness: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = roughness
        m.metalness.contents = metalness
        return m
    }

    static func wood(_ tint: UIColor, repeatU: Float, repeatV: Float, roughness: CGFloat = 0.45) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = tex("wood_albedo.jpg")
        m.multiply.contents = tint
        m.normal.contents = tex("wood_normal.png")
        m.normal.intensity = 0.35
        m.roughness.contents = roughness
        for p in [m.diffuse, m.normal] {
            p.contentsTransform = SCNMatrix4MakeScale(repeatU, repeatV, 1)
            p.wrapS = .repeat; p.wrapT = .repeat
            p.mipFilter = .linear; p.maxAnisotropy = 8
        }
        return m
    }

    static let chrome = plain(UIColor(white: 0.86, alpha: 1), roughness: 0.16, metalness: 1)
}

// MARK: - Un habit en volume : devant et dos, bombés, qui se rejoignent sur les bords

enum ClothMesh {
    /// Nœud de l'habit, le haut (col) à l'origine, le vêtement vers le bas, face avant vers +z.
    static func make(front: UIImage, back: UIImage?, width w: Float, seed: Float, depth: Float = 0.05, folds: Float = 0.012) -> SCNNode {
        let aspect = Float(front.size.height / max(1, front.size.width))
        let h = w * aspect
        let node = SCNNode()
        node.name = "cloth"
        let f = surface(width: w, height: h, side: 1, seed: seed, depth: depth, folds: folds)
        f.firstMaterial = Materials.fabric(front)
        let b = surface(width: w, height: h, side: -1, seed: seed, depth: depth * 0.8, folds: folds)
        b.firstMaterial = Materials.fabric(back ?? front.flippedHorizontally())
        let fn = SCNNode(geometry: f), bn = SCNNode(geometry: b)
        fn.castsShadow = true; bn.castsShadow = true
        node.addChildNode(fn)
        node.addChildNode(bn)
        return node
    }

    /// Une face : bombée au torse, plis en bas ; `side` = 1 (devant, vers +z) ou -1 (dos, vers -z).
    static func surface(width w: Float, height h: Float, side: Float, seed: Float, depth: Float, folds: Float) -> SCNGeometry {
        let nx = 24, ny = 34
        func z(_ u: Float, _ v: Float) -> Float {
            let x = u - 0.5
            // Volume du torse (maximum vers le haut du ventre), nul sur les bords pour fermer l'habit.
            let body = depth * max(0, cos(x * .pi)) * (0.45 + 0.55 * sin(min(1, v * 1.15) * .pi * 0.85 + 0.25))
            let hem = folds * v * v * sin(x * 21 + seed * 3) + folds * 0.5 * v * sin(x * 8.5 + seed)
            return side * body + hem
        }
        var verts: [SCNVector3] = [], norms: [SCNVector3] = [], uvs: [CGPoint] = []
        for j in 0...ny {
            for i in 0...nx {
                let u = Float(i) / Float(nx), v = Float(j) / Float(ny)
                let e: Float = 0.004
                let dzdx = (z(u + e, v) - z(u - e, v)) / (2 * e * w)
                let dzdy = (z(u, v + e) - z(u, v - e)) / (2 * e * h)
                var n = SIMD3<Float>(-dzdx, dzdy, 1) * side
                n = simd_normalize(n)
                verts.append(SCNVector3((u - 0.5) * w, -v * h, z(u, v)))
                norms.append(SCNVector3(n.x, n.y, n.z))
                // Le dos se lit de derrière : l'image est retournée.
                uvs.append(CGPoint(x: CGFloat(side > 0 ? u : 1 - u), y: CGFloat(v)))
            }
        }
        var idx: [Int32] = []
        let row = nx + 1
        for j in 0..<ny {
            for i in 0..<nx {
                let a = Int32(j * row + i), b = a + 1, c = Int32((j + 1) * row + i), d = c + 1
                if side > 0 { idx += [a, c, b, b, c, d] } else { idx += [a, b, c, b, d, c] }
            }
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms),
                                     SCNGeometrySource(textureCoordinates: uvs)],
                           elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    }
}

// MARK: - Une chaussure reconstruite à partir de ses silhouettes (enveloppe visuelle)

enum ShoeMesh {
    /// Longueur réelle d'après la pointure européenne (ex. 42,5 → 29,8 cm).
    static func length(forSize size: String) -> Float {
        let n = Float(size.replacingOccurrences(of: ",", with: ".").filter { "0123456789.".contains($0) }) ?? 0
        guard (30...52).contains(n) else { return 0.29 }
        return (n * 0.667 + 1.6) / 100
    }

    /// Nœud de la chaussure : posée au sol (y = 0), pointe en x = 0, talon en x = L, centrée en z.
    static func make(views: [PhotoView: UIImage], length L: Float) -> SCNNode? {
        guard let side = views[.side], let sideMap = AlphaMap(side) else { return nil }
        let H = L * Float(side.size.height / max(1, side.size.width))
        var W = L * 0.36
        if let top = views[.top] { W = L * Float(top.size.height / max(1, top.size.width)) }
        else if let front = views[.front] { W = H * Float(front.size.width / max(1, front.size.height)) }
        W = min(max(W, L * 0.25), L * 0.5)

        let topMap = views[.top].flatMap { AlphaMap($0) }
        let frontMap = views[.front].flatMap { AlphaMap($0) }
        let innerMap = views[.inner].flatMap { AlphaMap($0) }
        let rearMap = views[.rear].flatMap { AlphaMap($0) }

        // Grille de voxels (≈ 2 mm), avec une bordure vide pour fermer la surface.
        let nx = 132
        let s = L / Float(nx - 4)
        let ny = Int(H / s) + 4, nz = Int(W / s) + 4
        func world(_ i: Int, _ j: Int, _ k: Int) -> SIMD3<Float> {
            SIMD3(Float(i - 2) * s, Float(j - 2) * s, Float(k - 2) * s - W / 2)
        }
        var field = [Float](repeating: 0, count: nx * ny * nz)
        @inline(__always) func at(_ i: Int, _ j: Int, _ k: Int) -> Int { (k * ny + j) * nx + i }
        for k in 2..<(nz - 2) {
            for j in 2..<(ny - 2) {
                for i in 2..<(nx - 2) {
                    let p = world(i, j, k)
                    let ux = p.x / L, vy = 1 - p.y / H, wz = (p.z + W / 2) / W
                    var occ = sideMap.sample(ux, vy)
                    if occ < 0.5 { continue }
                    if let m = topMap { occ = min(occ, m.sample(ux, wz)); if occ < 0.5 { continue } }
                    if let m = frontMap { occ = min(occ, m.sample(wz, vy)); if occ < 0.5 { continue } }
                    if let m = innerMap { occ = min(occ, m.sample(1 - ux, vy)); if occ < 0.5 { continue } }
                    if let m = rearMap { occ = min(occ, m.sample(1 - wz, vy)) }
                    if topMap == nil && frontMap == nil {
                        // Sans vue de dessus : section arrondie.
                        let r = (p.z / (W / 2))
                        occ = min(occ, 1 - r * r * 0.9)
                    }
                    field[at(i, j, k)] = occ >= 0.5 ? 1 : 0
                }
            }
        }
        // Lissage (deux passes de flou 3 × 3 × 3) pour des formes arrondies, sans marches d'escalier.
        for _ in 0..<2 { field = blur(field, nx, ny, nz) }

        // Surface nets : un sommet par cellule traversée par la surface, des quads entre elles.
        let iso: Float = 0.5
        var cellVertex = [Int32](repeating: -1, count: nx * ny * nz)
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        let corners = [(0, 0, 0), (1, 0, 0), (0, 1, 0), (1, 1, 0), (0, 0, 1), (1, 0, 1), (0, 1, 1), (1, 1, 1)]
        let edges = [(0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7)]
        func grad(_ i: Int, _ j: Int, _ k: Int) -> SIMD3<Float> {
            let i0 = max(i - 1, 0), i1 = min(i + 1, nx - 1), j0 = max(j - 1, 0), j1 = min(j + 1, ny - 1)
            let k0 = max(k - 1, 0), k1 = min(k + 1, nz - 1)
            return SIMD3(field[at(i1, j, k)] - field[at(i0, j, k)], field[at(i, j1, k)] - field[at(i, j0, k)],
                         field[at(i, j, k1)] - field[at(i, j, k0)])
        }
        for k in 0..<(nz - 1) {
            for j in 0..<(ny - 1) {
                for i in 0..<(nx - 1) {
                    var vals = [Float](repeating: 0, count: 8)
                    var inside = 0
                    for (c, o) in corners.enumerated() {
                        vals[c] = field[at(i + o.0, j + o.1, k + o.2)]
                        if vals[c] > iso { inside += 1 }
                    }
                    if inside == 0 || inside == 8 { continue }
                    var sum = SIMD3<Float>(0, 0, 0), n: Float = 0
                    for e in edges {
                        let a = vals[e.0], b = vals[e.1]
                        if (a > iso) == (b > iso) { continue }
                        let t = (iso - a) / (b - a)
                        let pa = SIMD3<Float>(Float(corners[e.0].0), Float(corners[e.0].1), Float(corners[e.0].2))
                        let pb = SIMD3<Float>(Float(corners[e.1].0), Float(corners[e.1].1), Float(corners[e.1].2))
                        sum += pa + (pb - pa) * t
                        n += 1
                    }
                    let local = sum / n
                    let p = world(i, j, k) + local * s
                    cellVertex[at(i, j, k)] = Int32(positions.count)
                    positions.append(p)
                    let g = grad(i, j, k) + grad(i + 1, j + 1, k + 1)
                    normals.append(simd_length(g) > 0 ? -simd_normalize(g) : SIMD3(0, 1, 0))
                }
            }
        }
        // Quads : pour chaque arête de la grille qui traverse la surface.
        var tris: [(Int32, Int32, Int32)] = []
        func quad(_ a: Int32, _ b: Int32, _ c: Int32, _ d: Int32, _ flip: Bool) {
            guard a >= 0, b >= 0, c >= 0, d >= 0 else { return }
            if flip { tris.append((a, c, b)); tris.append((a, d, c)) } else { tris.append((a, b, c)); tris.append((a, c, d)) }
        }
        for k in 1..<(nz - 1) {
            for j in 1..<(ny - 1) {
                for i in 1..<(nx - 1) {
                    let inside = field[at(i, j, k)] > iso
                    if i < nx - 1, inside != (field[at(i + 1, j, k)] > iso) {
                        quad(cellVertex[at(i, j - 1, k - 1)], cellVertex[at(i, j, k - 1)], cellVertex[at(i, j, k)], cellVertex[at(i, j - 1, k)], !inside)
                    }
                    if j < ny - 1, inside != (field[at(i, j + 1, k)] > iso) {
                        quad(cellVertex[at(i - 1, j, k - 1)], cellVertex[at(i - 1, j, k)], cellVertex[at(i, j, k)], cellVertex[at(i, j, k - 1)], !inside)
                    }
                    if k < nz - 1, inside != (field[at(i, j, k + 1)] > iso) {
                        quad(cellVertex[at(i - 1, j - 1, k)], cellVertex[at(i, j - 1, k)], cellVertex[at(i, j, k)], cellVertex[at(i - 1, j, k)], !inside)
                    }
                }
            }
        }
        guard !tris.isEmpty else { return nil }

        // Textures projetées depuis chaque photo selon l'orientation de la face.
        enum Face: Int, CaseIterable { case outer, inner, top, sole, front, rear }
        var groups: [Face: (v: [SCNVector3], n: [SCNVector3], uv: [CGPoint])] = [:]
        func uv(_ f: Face, _ p: SIMD3<Float>) -> CGPoint {
            let ux = p.x / L, vy = 1 - p.y / H, wz = (p.z + W / 2) / W
            switch f {
            case .outer: return CGPoint(x: CGFloat(ux), y: CGFloat(vy))
            case .inner: return CGPoint(x: CGFloat(views[.inner] != nil ? 1 - ux : ux), y: CGFloat(vy))
            case .top: return CGPoint(x: CGFloat(ux), y: CGFloat(wz))
            case .front: return CGPoint(x: CGFloat(wz), y: CGFloat(vy))
            case .rear: return CGPoint(x: CGFloat(views[.rear] != nil ? 1 - wz : wz), y: CGFloat(vy))
            case .sole: return CGPoint(x: CGFloat(ux), y: CGFloat(wz))
            }
        }
        for t in tris {
            let fn = simd_normalize(normals[Int(t.0)] + normals[Int(t.1)] + normals[Int(t.2)])
            let ax = abs(fn.x), ay = abs(fn.y), az = abs(fn.z)
            let face: Face
            if ay >= ax && ay >= az { face = fn.y > 0 ? .top : .sole }
            else if az >= ax { face = fn.z > 0 ? .outer : .inner }
            else { face = fn.x < 0 ? .front : .rear }
            // Le dessus ne couvre que ce qui regarde vraiment vers le haut ; sinon on garde le profil (plus net).
            var f = face
            if face == .top && ay < 0.75 { f = az >= ax ? (fn.z > 0 ? .outer : .inner) : (fn.x < 0 ? .front : .rear) }
            if (f == .front && views[.front] == nil) || (f == .rear && views[.rear] == nil && views[.front] == nil) {
                f = fn.z >= 0 ? .outer : .inner
            }
            if f == .top && views[.top] == nil { f = fn.z >= 0 ? .outer : .inner }
            var g = groups[f] ?? ([], [], [])
            for idx in [t.0, t.1, t.2] {
                let p = positions[Int(idx)], n = normals[Int(idx)]
                g.v.append(SCNVector3(p.x, p.y, p.z))
                g.n.append(SCNVector3(n.x, n.y, n.z))
                g.uv.append(uv(f, p))
            }
            groups[f] = g
        }
        let solecolor = side.averageColor(v0: 0.9, v1: 1)
        let node = SCNNode()
        node.name = "shoe"
        for (face, g) in groups {
            let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: g.v), SCNGeometrySource(normals: g.n),
                                            SCNGeometrySource(textureCoordinates: g.uv)],
                                  elements: [SCNGeometryElement(indices: Array(0..<Int32(g.v.count)), primitiveType: .triangles)])
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.roughness.contents = 0.6
            m.isDoubleSided = true
            m.diffuse.wrapS = .clamp; m.diffuse.wrapT = .clamp
            m.diffuse.mipFilter = .linear
            switch face {
            case .outer: m.diffuse.contents = side
            case .inner: m.diffuse.contents = views[.inner] ?? side
            case .top: m.diffuse.contents = views[.top] ?? side
            case .front: m.diffuse.contents = views[.front] ?? side
            case .rear: m.diffuse.contents = views[.rear] ?? views[.front] ?? side
            case .sole: m.diffuse.contents = solecolor; m.roughness.contents = 0.85
            }
            geo.firstMaterial = m
            let n = SCNNode(geometry: geo)
            n.castsShadow = true
            node.addChildNode(n)
        }
        // Centre la chaussure (pointe vers -x avant rotation), posée sur y = 0.
        node.pivot = SCNMatrix4MakeTranslation(L / 2, 0, 0)
        return node
    }

    private static func blur(_ f: [Float], _ nx: Int, _ ny: Int, _ nz: Int) -> [Float] {
        var a = f, b = f
        func pass(_ src: [Float], _ dst: inout [Float], _ dx: Int, _ dy: Int, _ dz: Int) {
            for k in 0..<nz {
                for j in 0..<ny {
                    for i in 0..<nx {
                        let id = (k * ny + j) * nx + i
                        let i0 = max(0, i - dx), i1 = min(nx - 1, i + dx)
                        let j0 = max(0, j - dy), j1 = min(ny - 1, j + dy)
                        let k0 = max(0, k - dz), k1 = min(nz - 1, k + dz)
                        dst[id] = (src[(k0 * ny + j0) * nx + i0] + src[id] * 2 + src[(k1 * ny + j1) * nx + i1]) / 4
                    }
                }
            }
        }
        pass(a, &b, 1, 0, 0); pass(b, &a, 0, 1, 0); pass(a, &b, 0, 0, 1)
        return b
    }
}

// MARK: - Cintre en bois avec crochet en fil d'acier (dimensions réelles)

enum HangerModel {
    /// Origine = centre de la tringle. Le crochet l'entoure ; le corps du cintre est dessous, dans le plan x-y.
    static func make(width: Float = 0.43) -> SCNNode {
        let node = SCNNode()
        node.name = "hanger"

        // Corps : profil courbé, 12 mm d'épaisseur, bords arrondis.
        let mm: CGFloat = 1000
        let half = CGFloat(width / 2) * mm
        let p = UIBezierPath()
        p.move(to: CGPoint(x: -half, y: -70))
        p.addQuadCurve(to: CGPoint(x: 0, y: 0), controlPoint: CGPoint(x: -half * 0.45, y: -8))
        p.addQuadCurve(to: CGPoint(x: half, y: -70), controlPoint: CGPoint(x: half * 0.45, y: -8))
        p.addQuadCurve(to: CGPoint(x: half, y: -92), controlPoint: CGPoint(x: half + 13, y: -81))
        p.addQuadCurve(to: CGPoint(x: 0, y: -30), controlPoint: CGPoint(x: half * 0.5, y: -48))
        p.addQuadCurve(to: CGPoint(x: -half, y: -92), controlPoint: CGPoint(x: -half * 0.5, y: -48))
        p.addQuadCurve(to: CGPoint(x: -half, y: -70), controlPoint: CGPoint(x: -half - 13, y: -81))
        p.close()
        p.flatness = 0.5
        let shape = SCNShape(path: p, extrusionDepth: 12)
        shape.chamferRadius = 3
        shape.chamferMode = .both
        let beech = UIColor(red: 0.78, green: 0.58, blue: 0.40, alpha: 1)
        shape.firstMaterial = Materials.wood(beech, repeatU: 0.01, repeatV: 0.01, roughness: 0.32)
        let body = SCNNode(geometry: shape)
        body.scale = SCNVector3(0.001, 0.001, 0.001)
        body.position = SCNVector3(0, -0.062, 0)
        body.castsShadow = true
        node.addChildNode(body)

        // Crochet : fil de 5 mm qui sort du corps, monte et s'enroule autour de la tringle (rayon 12 mm).
        var pts: [SIMD3<Float>] = []
        let r: Float = 0.0155
        pts.append(SIMD3(0, -0.056, 0))
        pts.append(SIMD3(0, -0.04, 0))
        pts.append(SIMD3(-0.004, -0.028, 0))
        pts.append(SIMD3(-r, -0.008, 0))
        for a in stride(from: Float.pi, through: -0.35, by: -0.12) {
            pts.append(SIMD3(cos(a) * r, sin(a) * r, 0))
        }
        pts.append(SIMD3(cos(-0.35) * r + 0.004, sin(-0.35) * r - 0.006, 0))
        let hook = SCNNode(geometry: tube(pts, radius: 0.0025))
        hook.geometry?.firstMaterial = Materials.chrome
        hook.castsShadow = true
        node.addChildNode(hook)
        // Virole qui tient le crochet dans le bois.
        let ferrule = SCNCylinder(radius: 0.0045, height: 0.01)
        ferrule.firstMaterial = Materials.chrome
        let f = SCNNode(geometry: ferrule)
        f.position = SCNVector3(0, -0.058, 0)
        node.addChildNode(f)
        return node
    }

    /// Un tube rond qui suit une ligne (fil métallique).
    static func tube(_ pts: [SIMD3<Float>], radius: Float, segments: Int = 10) -> SCNGeometry {
        var verts: [SCNVector3] = [], norms: [SCNVector3] = []
        var idx: [Int32] = []
        for (i, p) in pts.enumerated() {
            let prev = pts[max(0, i - 1)], next = pts[min(pts.count - 1, i + 1)]
            let t = simd_normalize(next - prev)
            var up = SIMD3<Float>(0, 0, 1)
            if abs(simd_dot(up, t)) > 0.9 { up = SIMD3(1, 0, 0) }
            let n1 = simd_normalize(simd_cross(t, up)), n2 = simd_cross(t, n1)
            for s in 0...segments {
                let a = Float(s) / Float(segments) * 2 * .pi
                let n = n1 * cos(a) + n2 * sin(a)
                let v = p + n * radius
                verts.append(SCNVector3(v.x, v.y, v.z))
                norms.append(SCNVector3(n.x, n.y, n.z))
            }
        }
        let ring = segments + 1
        for i in 0..<(pts.count - 1) {
            for s in 0..<segments {
                let a = Int32(i * ring + s), b = a + 1, c = Int32((i + 1) * ring + s), d = c + 1
                idx += [a, c, b, b, c, d]
            }
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms)],
                           elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    }
}
