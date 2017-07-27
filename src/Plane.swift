import Foundation
import ARKit

let useOcclusionPlanes = false

class Plane: SCNNode {
    var anchor: ARPlaneAnchor
    var occlusionNode: SCNNode?
    let occlusionPlaneVerticalOffset: Float = -0.01  // The occlusion plane should be placed 1 cm below the actual plane to avoid z-fighting etc.
    var debugVisualization: PlaneDebugVisualization?

    init(_ anchor: ARPlaneAnchor, _ showDebugVisualization: Bool) {
        self.anchor = anchor

        super.init()

        self.showDebugVisualization(showDebugVisualization)

        if useOcclusionPlanes {
            createOcclusionNode()
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ anchor: ARPlaneAnchor) {
        self.anchor = anchor
        debugVisualization?.update(anchor)

        if useOcclusionPlanes {
            updateOcclusionNode()
        }
    }

    func showDebugVisualization(_ show: Bool) {
        if show {
            if debugVisualization == nil {
                DispatchQueue.global().async {
                    self.debugVisualization = PlaneDebugVisualization(anchor: self.anchor)
                    DispatchQueue.main.async {
                        self.addChildNode(self.debugVisualization!)
                    }
                }
            }
        } else {
            debugVisualization?.removeFromParentNode()
            debugVisualization = nil
        }
    }

    func updateOcclusionSetting() {
        if useOcclusionPlanes {
            if occlusionNode == nil {
                createOcclusionNode()
            }
        } else {
            occlusionNode?.removeFromParentNode()
            occlusionNode = nil
        }
    }

    private func createOcclusionNode() {
        // Make the occlusion geometry slightly smaller than the plane.
        let occlusionPlane = SCNPlane(width: CGFloat(anchor.extent.x - 0.05), height: CGFloat(anchor.extent.z - 0.05))
        let material = SCNMaterial()
        material.colorBufferWriteMask = []
        material.isDoubleSided = true
        occlusionPlane.materials = [material]

        occlusionNode = SCNNode()
        occlusionNode!.geometry = occlusionPlane
        occlusionNode!.transform = SCNMatrix4MakeRotation(-Float.pi / 2.0, 1, 0, 0)
        occlusionNode!.position = SCNVector3Make(anchor.center.x, occlusionPlaneVerticalOffset, anchor.center.z)

        self.addChildNode(occlusionNode!)
    }

    private func updateOcclusionNode() {
        guard let occlusionNode = occlusionNode, let occlusionPlane = occlusionNode.geometry as? SCNPlane else {
            return
        }
        occlusionPlane.width = CGFloat(anchor.extent.x - 0.05)
        occlusionPlane.height = CGFloat(anchor.extent.z - 0.05)

        occlusionNode.position = SCNVector3Make(anchor.center.x, occlusionPlaneVerticalOffset, anchor.center.z)
    }
}

class PlaneDebugVisualization: SCNNode {
    var planeAnchor: ARPlaneAnchor
    var planeGeometry: SCNPlane
    var planeNode: SCNNode

    init(anchor: ARPlaneAnchor) {

        self.planeAnchor = anchor

        let grid = UIImage(named: "Models.scnassets/plane_grid.png")
        self.planeGeometry = createPlane(size: CGSize(width: CGFloat(anchor.extent.x), height: CGFloat(anchor.extent.z)), contents: grid)
        self.planeNode = SCNNode(geometry: planeGeometry)
        self.planeNode.transform = SCNMatrix4MakeRotation(-Float.pi / 2.0, 1, 0, 0)

        super.init()

        let originVisualizationNode = createAxesNode(quiverLength: 0.1, quiverThickness: 1.0)
        self.addChildNode(originVisualizationNode)
        self.addChildNode(planeNode)

        self.position = SCNVector3(anchor.center.x, -0.002, anchor.center.z) // 2 mm below the origin of plane.

        adjustScale()
    }

    func update(_ anchor: ARPlaneAnchor) {
        self.planeAnchor = anchor

        self.planeGeometry.width = CGFloat(anchor.extent.x)
        self.planeGeometry.height = CGFloat(anchor.extent.z)

        self.position = SCNVector3Make(anchor.center.x, -0.002, anchor.center.z)

        adjustScale()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func adjustScale() {
        let scaledWidth: Float = Float(planeGeometry.width / 2.4)
        let scaledHeight: Float = Float(planeGeometry.height / 2.4)

        let offsetWidth: Float = -0.5 * (scaledWidth - 1)
        let offsetHeight: Float = -0.5 * (scaledHeight - 1)

        let material = self.planeGeometry.materials.first
        var transform = SCNMatrix4MakeScale(scaledWidth, scaledHeight, 1)
        transform = SCNMatrix4Translate(transform, offsetWidth, offsetHeight, 0)
        material?.diffuse.contentsTransform = transform

    }
}

func material(withDiffuse diffuse: Any?, respondsToLighting: Bool = true) -> SCNMaterial {
    let material = SCNMaterial()
    material.diffuse.contents = diffuse
    material.isDoubleSided = true
    if respondsToLighting {
        material.locksAmbientWithDiffuse = true
    } else {
        material.ambient.contents = UIColor.black
        material.lightingModel = .constant
        material.emission.contents = diffuse
    }
    return material
}

func createPlane(size: CGSize, contents: AnyObject?) -> SCNPlane {
    let plane = SCNPlane(width: size.width, height: size.height)
    plane.materials = [material(withDiffuse: contents)]
    return plane
}

func createAxesNode(quiverLength: CGFloat, quiverThickness: CGFloat) -> SCNNode {
    let quiverThickness = (quiverLength / 50.0) * quiverThickness
    let chamferRadius = quiverThickness / 2.0

    let xQuiverBox = SCNBox(width: quiverLength, height: quiverThickness, length: quiverThickness, chamferRadius: chamferRadius)
    xQuiverBox.materials = [material(withDiffuse: UIColor.red, respondsToLighting: false)]
    let xQuiverNode = SCNNode(geometry: xQuiverBox)
    xQuiverNode.position = SCNVector3Make(Float(quiverLength / 2.0), 0.0, 0.0)

    let yQuiverBox = SCNBox(width: quiverThickness, height: quiverLength, length: quiverThickness, chamferRadius: chamferRadius)
    yQuiverBox.materials = [material(withDiffuse: UIColor.green, respondsToLighting: false)]
    let yQuiverNode = SCNNode(geometry: yQuiverBox)
    yQuiverNode.position = SCNVector3Make(0.0, Float(quiverLength / 2.0), 0.0)

    let zQuiverBox = SCNBox(width: quiverThickness, height: quiverThickness, length: quiverLength, chamferRadius: chamferRadius)
    zQuiverBox.materials = [material(withDiffuse: UIColor.blue, respondsToLighting: false)]
    let zQuiverNode = SCNNode(geometry: zQuiverBox)
    zQuiverNode.position = SCNVector3Make(0.0, 0.0, Float(quiverLength / 2.0))

    let quiverNode = SCNNode()
    quiverNode.addChildNode(xQuiverNode)
    quiverNode.addChildNode(yQuiverNode)
    quiverNode.addChildNode(zQuiverNode)
    quiverNode.name = "Axes"
    return quiverNode
}
