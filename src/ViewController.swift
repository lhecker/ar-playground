import UIKit
import SceneKit
import ARKit

class ViewController: UIViewController, ARSCNViewDelegate {
    let sceneView = ARSCNView()

    override func loadView() {
        self.view = sceneView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        sceneView.delegate = self
        sceneView.showsStatistics = true
        sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints]
        sceneView.autoenablesDefaultLighting = true

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(sceneViewTapped))
        sceneView.gestureRecognizers = [tapGestureRecognizer]

        let scene = SCNScene()
        sceneView.scene = scene
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        let cfg = ARWorldTrackingSessionConfiguration()
        cfg.planeDetection = .horizontal
        sceneView.session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Pause the view's session
        sceneView.session.pause()
    }

    var previousNode: SCNNode?

    @objc func sceneViewTapped(gestureRecognizer: UIGestureRecognizer) {
        let location = gestureRecognizer.location(in: sceneView)
        let (worldPos, planeAnchor, hitPlane) = worldPositionFromScreenPosition(location, objectPos: nil)

        NSLog("tapped at \(location) -> \(worldPos?.friendlyString() ?? "n/a"), \(planeAnchor?.description ?? "n/a"), \(hitPlane)")

        if let worldPos = worldPos {
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.red
            material.specular.contents = UIColor.white

            let sphere = SCNSphere(radius: 0.01)
            sphere.materials = [material]

            let node = SCNNode(geometry: sphere)
            node.worldPosition = worldPos
            sceneView.scene.rootNode.addChildNode(node)

            if let previousNode = previousNode {
                let distanceVector = node.worldPosition - previousNode.worldPosition
                let distance = distanceVector.length()

                do {
                    let zAlign = SCNNode()
                    zAlign.eulerAngles.x = Float.pi / 2

                    let material = SCNMaterial()
                    material.transparency = 0.75
                    material.diffuse.contents = UIColor.green
                    material.specular.contents = UIColor.white

                    let cylinder = SCNCylinder(radius: 0.005, height: CGFloat(distance))
                    cylinder.materials = [material]

                    let cylinderNode = SCNNode(geometry: cylinder)
                    cylinderNode.position.y = distance / -2
                    zAlign.addChildNode(cylinderNode)

                    let containerNode = SCNNode()
                    containerNode.worldPosition = previousNode.worldPosition
                    containerNode.constraints = [SCNLookAtConstraint(target: node)]
                    containerNode.addChildNode(zAlign)

                    sceneView.scene.rootNode.addChildNode(containerNode)
                }

                do {
                    let material = SCNMaterial()
                    material.diffuse.contents = UIColor.green
                    material.specular.contents = UIColor.white

                    let label = SCNText(string: String(format: "%.5f", distance), extrusionDepth: 1)
                    label.font = UIFont.systemFont(ofSize: 36)
                    label.containerFrame = CGRect(x: 0, y: 0, width: 0, height: 2 * 36)
                    label.materials = [material]

                    let labelNode = SCNNode(geometry: label)
                    labelNode.worldPosition = previousNode.worldPosition + (distanceVector / 2)
                    labelNode.constraints = [
                        SCNBillboardConstraint(),
                        SCNTransformConstraint(inWorldSpace: false, with: { (_, m) -> SCNMatrix4 in
                            let scaleFactor = Float(1.0 / 500.0)
                            return SCNMatrix4Scale(m, scaleFactor, scaleFactor, scaleFactor)
                        }),
                    ]
                    sceneView.scene.rootNode.addChildNode(labelNode)
                }
            }

            previousNode = node
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        let alert = UIAlertController(title: "Session Error", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "", style: .cancel, handler: { _ in alert.dismiss(animated: true) }))
        self.present(alert, animated: true)
    }

    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
    }

    // MARK: - Planes

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        DispatchQueue.main.async {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                self.addPlane(node: node, anchor: planeAnchor)
                self.checkIfObjectShouldMoveOntoPlane(anchor: planeAnchor)
            }
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        DispatchQueue.main.async {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                self.updatePlane(anchor: planeAnchor)
                self.checkIfObjectShouldMoveOntoPlane(anchor: planeAnchor)
            }
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        DispatchQueue.main.async {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                self.removePlane(anchor: planeAnchor)
            }
        }
    }

    private var planes = [ARPlaneAnchor : Plane]()
    private let showDebugVisuals = true

    private func addPlane(node: SCNNode, anchor: ARPlaneAnchor) {
        let plane = Plane(anchor, showDebugVisuals)
        planes[anchor] = plane
        node.addChildNode(plane)
    }

    private func updatePlane(anchor: ARPlaneAnchor) {
        if let plane = planes[anchor] {
            plane.update(anchor)
        }
    }

    private func removePlane(anchor: ARPlaneAnchor) {
        if let plane = planes.removeValue(forKey: anchor) {
            plane.removeFromParentNode()
        }
    }

    private func checkIfObjectShouldMoveOntoPlane(anchor: ARPlaneAnchor) {
        /*guard let object = virtualObject, let planeAnchorNode = sceneView.node(for: anchor) else {
         return
         }

         // Get the object's position in the plane's coordinate system.
         let objectPos = planeAnchorNode.convertPosition(object.position, from: object.parent)

         if objectPos.y == 0 {
         return; // The object is already on the plane - nothing to do here.
         }

         // Add 10% tolerance to the corners of the plane.
         let tolerance: Float = 0.1

         let minX: Float = anchor.center.x - anchor.extent.x / 2 - anchor.extent.x * tolerance
         let maxX: Float = anchor.center.x + anchor.extent.x / 2 + anchor.extent.x * tolerance
         let minZ: Float = anchor.center.z - anchor.extent.z / 2 - anchor.extent.z * tolerance
         let maxZ: Float = anchor.center.z + anchor.extent.z / 2 + anchor.extent.z * tolerance

         if objectPos.x < minX || objectPos.x > maxX || objectPos.z < minZ || objectPos.z > maxZ {
         return
         }

         // Drop the object onto the plane if it is near it.
         let verticalAllowance: Float = 0.03
         if objectPos.y > -verticalAllowance && objectPos.y < verticalAllowance {
         SCNTransaction.begin()
         SCNTransaction.animationDuration = 0.5
         SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
         object.position.y = anchor.transform.columns.3.y
         SCNTransaction.commit()
         }*/
    }

    private func worldPositionFromScreenPosition(_ position: CGPoint, objectPos: SCNVector3?, infinitePlane: Bool = false) -> (position: SCNVector3?, planeAnchor: ARPlaneAnchor?, hitAPlane: Bool) {

        // -------------------------------------------------------------------------------
        // 1. Always do a hit test against exisiting plane anchors first.
        //    (If any such anchors exist & only within their extents.)

        let planeHitTestResults = sceneView.hitTest(position, types: .existingPlaneUsingExtent)
        if let result = planeHitTestResults.first {

            let planeHitTestPosition = SCNVector3Make(result.worldTransform.columns.3.x, result.worldTransform.columns.3.y, result.worldTransform.columns.3.z)
            let planeAnchor = result.anchor

            // Return immediately - this is the best possible outcome.
            return (planeHitTestPosition, planeAnchor as? ARPlaneAnchor, true)
        }

        // -------------------------------------------------------------------------------
        // 2. Collect more information about the environment by hit testing against
        //    the feature point cloud, but do not return the result yet.

        var featureHitTestPosition: SCNVector3?
        var highQualityFeatureHitTestResult = false

        let highQualityfeatureHitTestResults = hitTestWithFeatures(position, coneOpeningAngleInDegrees: 18, minDistance: 0.2, maxDistance: 2.0)

        if !highQualityfeatureHitTestResults.isEmpty {
            let result = highQualityfeatureHitTestResults[0]
            featureHitTestPosition = result.position
            highQualityFeatureHitTestResult = true
        }

        // -------------------------------------------------------------------------------
        // 3. If desired or necessary (no good feature hit test result): Hit test
        //    against an infinite, horizontal plane (ignoring the real world).

        let dragOnInfinitePlanesEnabled = false
        if (infinitePlane && dragOnInfinitePlanesEnabled) || !highQualityFeatureHitTestResult {

            let pointOnPlane = objectPos ?? SCNVector3Zero

            let pointOnInfinitePlane = hitTestWithInfiniteHorizontalPlane(position, pointOnPlane)
            if pointOnInfinitePlane != nil {
                return (pointOnInfinitePlane, nil, true)
            }
        }

        // -------------------------------------------------------------------------------
        // 4. If available, return the result of the hit test against high quality
        //    features if the hit tests against infinite planes were skipped or no
        //    infinite plane was hit.

        if highQualityFeatureHitTestResult {
            return (featureHitTestPosition, nil, false)
        }

        // -------------------------------------------------------------------------------
        // 5. As a last resort, perform a second, unfiltered hit test against features.
        //    If there are no features in the scene, the result returned here will be nil.

        let unfilteredFeatureHitTestResults = hitTestWithFeatures(position)
        if !unfilteredFeatureHitTestResults.isEmpty {
            let result = unfilteredFeatureHitTestResults[0]
            return (result.position, nil, false)
        }

        return (nil, nil, false)
    }

    struct FeatureHitTestResult {
        let position: SCNVector3
        let distanceToRayOrigin: Float
        let featureHit: SCNVector3
        let featureDistanceToHitResult: Float
    }

    func hitTestWithInfiniteHorizontalPlane(_ point: CGPoint, _ pointOnPlane: SCNVector3) -> SCNVector3? {
        guard let ray = hitTestRayFromScreenPos(point) else {
            return nil
        }

        // Do not intersect with planes above the camera or if the ray is almost parallel to the plane.
        if ray.direction.y > -0.03 {
            return nil
        }

        // Return the intersection of a ray from the camera through the screen position with a horizontal plane
        // at height (Y axis).
        return rayIntersectionWithHorizontalPlane(rayOrigin: ray.origin, direction: ray.direction, planeY: pointOnPlane.y)
    }

    func rayIntersectionWithHorizontalPlane(rayOrigin: SCNVector3, direction: SCNVector3, planeY: Float) -> SCNVector3? {

        let direction = direction.normalized()

        // Special case handling: Check if the ray is horizontal as well.
        if direction.y == 0 {
            if rayOrigin.y == planeY {
                // The ray is horizontal and on the plane, thus all points on the ray intersect with the plane.
                // Therefore we simply return the ray origin.
                return rayOrigin
            } else {
                // The ray is parallel to the plane and never intersects.
                return nil
            }
        }

        // The distance from the ray's origin to the intersection point on the plane is:
        //   (pointOnPlane - rayOrigin) dot planeNormal
        //  --------------------------------------------
        //          direction dot planeNormal

        // Since we know that horizontal planes have normal (0, 1, 0), we can simplify this to:
        let dist = (planeY - rayOrigin.y) / direction.y

        // Do not return intersections behind the ray's origin.
        if dist < 0 {
            return nil
        }

        // Return the intersection point.
        return rayOrigin + (direction * dist)
    }

    private func hitTestWithFeatures(_ point: CGPoint) -> [FeatureHitTestResult] {
        var results = [FeatureHitTestResult]()

        guard let ray = hitTestRayFromScreenPos(point) else {
            return results
        }

        if let result = hitTestFromOrigin(origin: ray.origin, direction: ray.direction) {
            results.append(result)
        }

        return results
    }

    private func hitTestFromOrigin(origin: SCNVector3, direction: SCNVector3) -> FeatureHitTestResult? {
        guard let features = sceneView.session.currentFrame?.rawFeaturePoints else {
            return nil
        }

        let points = features.points

        // Determine the point from the whole point cloud which is closest to the hit test ray.
        var closestFeaturePoint = origin
        var minDistance = Float.greatestFiniteMagnitude

        for i in 0...features.count {
            let feature = points.advanced(by: Int(i))
            let featurePos = SCNVector3(feature.pointee)

            let originVector = origin - featurePos
            let crossProduct = originVector.cross(direction)
            let featureDistanceFromResult = crossProduct.length()

            if featureDistanceFromResult < minDistance {
                closestFeaturePoint = featurePos
                minDistance = featureDistanceFromResult
            }
        }

        // Compute the point along the ray that is closest to the selected feature.
        let originToFeature = closestFeaturePoint - origin
        let hitTestResult = origin + (direction * direction.dot(originToFeature))
        let hitTestResultDistance = (hitTestResult - origin).length()

        return FeatureHitTestResult(position: hitTestResult, distanceToRayOrigin: hitTestResultDistance, featureHit: closestFeaturePoint, featureDistanceToHitResult: minDistance)
    }

    private func hitTestWithFeatures(_ point: CGPoint, coneOpeningAngleInDegrees: Float, minDistance: Float = 0, maxDistance: Float = Float.greatestFiniteMagnitude, maxResults: Int = 1) -> [FeatureHitTestResult] {
        var results = [FeatureHitTestResult]()

        guard let features = sceneView.session.currentFrame?.rawFeaturePoints else {
            return results
        }

        guard let ray = hitTestRayFromScreenPos(point) else {
            return results
        }

        let maxAngleInDeg = min(coneOpeningAngleInDegrees, 360) / 2
        let maxAngle = ((maxAngleInDeg / 180) * Float.pi)

        let points = features.points

        for i in 0...features.count {

            let feature = points.advanced(by: Int(i))
            let featurePos = SCNVector3(feature.pointee)

            let originToFeature = featurePos - ray.origin

            let crossProduct = originToFeature.cross(ray.direction)
            let featureDistanceFromResult = crossProduct.length()

            let hitTestResult = ray.origin + (ray.direction * ray.direction.dot(originToFeature))
            let hitTestResultDistance = (hitTestResult - ray.origin).length()

            if hitTestResultDistance < minDistance || hitTestResultDistance > maxDistance {
                // Skip this feature - it is too close or too far away.
                continue
            }

            let originToFeatureNormalized = originToFeature.normalized()
            let angleBetweenRayAndFeature = acos(ray.direction.dot(originToFeatureNormalized))

            if angleBetweenRayAndFeature > maxAngle {
                // Skip this feature - is is outside of the hit test cone.
                continue
            }

            // All tests passed: Add the hit against this feature to the results.
            results.append(FeatureHitTestResult(position: hitTestResult, distanceToRayOrigin: hitTestResultDistance, featureHit: featurePos, featureDistanceToHitResult: featureDistanceFromResult))
        }

        // Sort the results by feature distance to the ray.
        results = results.sorted(by: { (first, second) -> Bool in
            return first.distanceToRayOrigin < second.distanceToRayOrigin
        })

        // Cap the list to maxResults.
        var cappedResults = [FeatureHitTestResult]()
        var i = 0
        while i < maxResults && i < results.count {
            cappedResults.append(results[i])
            i += 1
        }

        return cappedResults
    }

    struct HitTestRay {
        let origin: SCNVector3
        let direction: SCNVector3
    }

    private func hitTestRayFromScreenPos(_ point: CGPoint) -> HitTestRay? {
        guard let frame = sceneView.session.currentFrame else {
            return nil
        }

        let transform = frame.camera.transform
        let cameraPos = SCNVector3Make(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)

        // Note: z: 1.0 will unproject() the screen position to the far clipping plane.
        let positionVec = SCNVector3(x: Float(point.x), y: Float(point.y), z: 1.0)
        let screenPosOnFarClippingPlane = sceneView.unprojectPoint(positionVec)

        var rayDirection = screenPosOnFarClippingPlane - cameraPos
        rayDirection.normalize()
        return HitTestRay(origin: cameraPos, direction: rayDirection)
    }
}

