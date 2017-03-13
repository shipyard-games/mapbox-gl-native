//
//  GameViewController.swift
//  SceneKitTesting
//
//  Created by Teemu Harju on 12/03/2017.
//  Copyright © 2017 Mapbox. All rights reserved.
//

import UIKit
import QuartzCore
import SceneKit
import Mapbox

class GameViewController: UIViewController {
    
    @IBOutlet weak var scnView: SCNView!
    @IBOutlet weak var mapView: MGLMapView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // create a new scene
        let scene = SCNScene(named: "art.scnassets/ship.scn")!
        
        // create and add a camera to the scene
        let cameraNode = SCNNode()
        cameraNode.name = "camera"
        cameraNode.camera = SCNCamera()
        scene.rootNode.addChildNode(cameraNode)
        
        // place the camera
        cameraNode.position = SCNVector3(x: 0, y: 15, z: 15)
        cameraNode.eulerAngles = SCNVector3(x: -45.0, y: 0.0, z: 0.0)
        
        // set the scene to the view
        scnView.scene = scene
        
        // allows the user to manipulate the camera
        scnView.allowsCameraControl = false
        
        // show statistics such as fps and timing information
        scnView.showsStatistics = true
        
        // configure the view
        scnView.backgroundColor = UIColor.clear
        
//        // add a tap gesture recognizer
//        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
//        scnView.addGestureRecognizer(tapGesture)
        
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        scnView.addGestureRecognizer(panGesture)
        
        let mapCamera = MGLMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: 60.1696973, longitude: 24.9333033), fromDistance: 300.0, pitch: 45.0, heading: 0.0)
        mapView.fly(to: mapCamera, completionHandler: {
            let _ = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true, block: {
                _ in
                
//                self.mapView.move(byDeltaX: 1.0, deltaY: 1.0)
            })
        })
    }
    
    func handlePan(_ gestureRecognizer: UIPanGestureRecognizer) {
        let delta = gestureRecognizer.translation(in: scnView)
        
        mapView.move(byDeltaX: Float(delta.x / 20.0), deltaY: Float(delta.y / 20.0))
        
        let cameraNode = scnView.scene!.rootNode.childNode(withName: "camera", recursively: false)!
        let newPosition = SCNVector3(x: cameraNode.position.x - Float(delta.x / 700.0),
                                     y: cameraNode.position.y,
                                     z: cameraNode.position.z - Float(delta.y / 600.0))
        cameraNode.position = newPosition
    }
    
    func handleTap(_ gestureRecognize: UIGestureRecognizer) {        
        // check what nodes are tapped
        let p = gestureRecognize.location(in: scnView)
        let hitResults = scnView.hitTest(p, options: [:])
        // check that we clicked on at least one object
        if hitResults.count > 0 {
            // retrieved the first clicked object
            let result: AnyObject = hitResults[0]
            
            // get its material
            let material = result.node!.geometry!.firstMaterial!
            
            // highlight it
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.5
            
            // on completion - unhighlight
            SCNTransaction.completionBlock = {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.5
                
                material.emission.contents = UIColor.black
                
                SCNTransaction.commit()
            }
            
            material.emission.contents = UIColor.red
            
            SCNTransaction.commit()
        }
    }
    
    override var shouldAutorotate: Bool {
        return true
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }

}
