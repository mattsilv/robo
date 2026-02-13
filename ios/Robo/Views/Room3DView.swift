import SwiftUI
import SceneKit

struct Room3DView: UIViewRepresentable {
    let room: RoomScanRecord

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.allowsCameraControl = true
        scnView.antialiasingMode = .multisampling4X
        scnView.backgroundColor = .clear
        scnView.autoenablesDefaultLighting = false

        let scene = buildScene()
        scnView.scene = scene
        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    // MARK: - Scene Construction

    private func buildScene() -> SCNScene {
        let scene = SCNScene()

        guard let summary = parseSummary() else { return scene }

        let walls = summary.walls
        let floorPolygon = summary.floorPolygon
        let ceilingHeight = summary.ceilingHeight

        // Compute centroid for camera targeting
        let centroid = computeCentroid(walls: walls, floorPolygon: floorPolygon)

        // Floor
        if floorPolygon.count >= 3 {
            let floorNode = makeFloorNode(polygon: floorPolygon)
            scene.rootNode.addChildNode(floorNode)
        }

        // Walls
        for wall in walls {
            let wallNode = makeWallNode(wall: wall)
            scene.rootNode.addChildNode(wallNode)

            // Dimension label on wall
            let label = makeLabelNode(text: formatFeetInches(wall.widthFt), position: SCNVector3(
                Float(wall.centerX),
                Float(wall.heightFt * 0.5 + 0.3),
                Float(wall.centerZ)
            ))
            scene.rootNode.addChildNode(label)
        }

        // Ceiling (semi-transparent)
        if ceilingHeight > 0, floorPolygon.count >= 3 {
            let ceilingNode = makeCeilingNode(polygon: floorPolygon, height: ceilingHeight)
            scene.rootNode.addChildNode(ceilingNode)
        }

        // Lighting
        addLighting(to: scene, centroid: centroid, ceilingHeight: ceilingHeight)

        // Camera
        addCamera(to: scene, centroid: centroid, ceilingHeight: ceilingHeight, walls: walls)

        return scene
    }

    // MARK: - Parsing

    private struct WallInfo {
        let centerX: Double
        let centerZ: Double
        let widthFt: Double
        let heightFt: Double
        let rotationDeg: Double
    }

    private struct RoomSummary {
        let walls: [WallInfo]
        let floorPolygon: [(x: Double, y: Double)]
        let ceilingHeight: Double
    }

    private func parseSummary() -> RoomSummary? {
        guard let dict = try? JSONSerialization.jsonObject(with: room.summaryJSON) as? [String: Any] else {
            return nil
        }

        // Walls
        let wallDicts = dict["walls"] as? [[String: Any]] ?? []
        let walls = wallDicts.compactMap { w -> WallInfo? in
            guard let cx = w["center_x_ft"] as? Double,
                  let cz = w["center_y_ft"] as? Double,
                  let width = w["width_ft"] as? Double,
                  let height = w["height_ft"] as? Double,
                  let rot = w["rotation_deg"] as? Double else { return nil }
            return WallInfo(centerX: cx, centerZ: cz, widthFt: width, heightFt: height, rotationDeg: rot)
        }

        // Floor polygon
        let polygonArray = dict["floor_polygon_2d_ft"] as? [[String: Double]] ?? []
        let floorPolygon = polygonArray.compactMap { p -> (x: Double, y: Double)? in
            guard let x = p["x"], let y = p["y"] else { return nil }
            return (x: x, y: y)
        }

        let ceilingHeight = dict["ceiling_height_ft"] as? Double ?? 0

        return RoomSummary(walls: walls, floorPolygon: floorPolygon, ceilingHeight: ceilingHeight)
    }

    // MARK: - Node Builders

    private func makeFloorNode(polygon: [(x: Double, y: Double)]) -> SCNNode {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: polygon[0].x, y: polygon[0].y))
        for i in 1..<polygon.count {
            path.addLine(to: CGPoint(x: polygon[i].x, y: polygon[i].y))
        }
        path.close()

        let shape = SCNShape(path: path, extrusionDepth: 0.05)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.3)
        material.isDoubleSided = true
        shape.materials = [material]

        let node = SCNNode(geometry: shape)
        // SCNShape extrudes along Z, but floor should be in XZ plane
        // Rotate -90 degrees around X to lay it flat
        node.eulerAngles.x = -.pi / 2
        return node
    }

    private func makeWallNode(wall: WallInfo) -> SCNNode {
        let thickness: CGFloat = 0.3
        let box = SCNBox(
            width: CGFloat(wall.widthFt),
            height: CGFloat(wall.heightFt),
            length: thickness,
            chamferRadius: 0
        )
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.systemGray4.withAlphaComponent(0.6)
        material.isDoubleSided = true
        box.materials = [material]

        let node = SCNNode(geometry: box)
        node.position = SCNVector3(
            Float(wall.centerX),
            Float(wall.heightFt / 2),
            Float(wall.centerZ)
        )
        node.eulerAngles.y = Float(-wall.rotationDeg * .pi / 180)
        return node
    }

    private func makeCeilingNode(polygon: [(x: Double, y: Double)], height: Double) -> SCNNode {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: polygon[0].x, y: polygon[0].y))
        for i in 1..<polygon.count {
            path.addLine(to: CGPoint(x: polygon[i].x, y: polygon[i].y))
        }
        path.close()

        let shape = SCNShape(path: path, extrusionDepth: 0.02)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white.withAlphaComponent(0.15)
        material.isDoubleSided = true
        shape.materials = [material]

        let node = SCNNode(geometry: shape)
        node.eulerAngles.x = -.pi / 2
        node.position.y = Float(height)
        return node
    }

    private func makeLabelNode(text: String, position: SCNVector3) -> SCNNode {
        let scnText = SCNText(string: text, extrusionDepth: 0.01)
        scnText.font = UIFont.systemFont(ofSize: 0.35, weight: .bold)
        scnText.flatness = 0.1
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white
        scnText.materials = [material]

        let node = SCNNode(geometry: scnText)
        // Center the text at its position
        let (min, max) = node.boundingBox
        let dx = (max.x - min.x) / 2
        let dy = (max.y - min.y) / 2
        node.pivot = SCNMatrix4MakeTranslation(dx, dy, 0)
        node.position = position
        node.constraints = [SCNBillboardConstraint()]
        return node
    }

    // MARK: - Camera & Lighting

    private func addCamera(to scene: SCNScene, centroid: SCNVector3, ceilingHeight: Double, walls: [WallInfo]) {
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.automaticallyAdjustsZRange = true

        // Position: above and back from centroid
        let roomSpan = estimateRoomSpan(walls: walls)
        let distance = Float(max(roomSpan, 15)) * 1.2
        cameraNode.position = SCNVector3(
            centroid.x,
            Float(max(ceilingHeight, 8)) * 1.5,
            centroid.z + distance * 0.6
        )
        cameraNode.look(at: centroid)
        scene.rootNode.addChildNode(cameraNode)
    }

    private func addLighting(to scene: SCNScene, centroid: SCNVector3, ceilingHeight: Double) {
        // Ambient
        let ambientNode = SCNNode()
        ambientNode.light = SCNLight()
        ambientNode.light?.type = .ambient
        ambientNode.light?.intensity = 400
        ambientNode.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambientNode)

        // Directional (from above)
        let dirNode = SCNNode()
        dirNode.light = SCNLight()
        dirNode.light?.type = .directional
        dirNode.light?.intensity = 600
        dirNode.light?.color = UIColor.white
        dirNode.position = SCNVector3(centroid.x, Float(ceilingHeight) + 10, centroid.z)
        dirNode.eulerAngles.x = -.pi / 3
        scene.rootNode.addChildNode(dirNode)
    }

    // MARK: - Helpers

    private func computeCentroid(walls: [WallInfo], floorPolygon: [(x: Double, y: Double)]) -> SCNVector3 {
        if floorPolygon.count >= 3 {
            let cx = floorPolygon.reduce(0.0) { $0 + $1.x } / Double(floorPolygon.count)
            let cz = floorPolygon.reduce(0.0) { $0 + $1.y } / Double(floorPolygon.count)
            return SCNVector3(Float(cx), 0, Float(cz))
        }
        guard !walls.isEmpty else { return SCNVector3Zero }
        let cx = walls.reduce(0.0) { $0 + $1.centerX } / Double(walls.count)
        let cz = walls.reduce(0.0) { $0 + $1.centerZ } / Double(walls.count)
        return SCNVector3(Float(cx), 0, Float(cz))
    }

    private func estimateRoomSpan(walls: [WallInfo]) -> Double {
        guard !walls.isEmpty else { return 10 }
        let xs = walls.map(\.centerX)
        let zs = walls.map(\.centerZ)
        let dx = (xs.max() ?? 0) - (xs.min() ?? 0)
        let dz = (zs.max() ?? 0) - (zs.min() ?? 0)
        return max(dx, dz)
    }

    private func formatFeetInches(_ feet: Double) -> String {
        let wholeFeet = Int(feet)
        let inches = Int((feet - Double(wholeFeet)) * 12.0 + 0.5)
        if inches == 0 || inches == 12 {
            return "\(inches == 12 ? wholeFeet + 1 : wholeFeet)\u{2032}"
        }
        return "\(wholeFeet)\u{2032}\(inches)\u{2033}"
    }
}
