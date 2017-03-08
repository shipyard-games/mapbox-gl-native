//
//  ViewController.swift
//  SingleViewApp
//
//  Created by Teemu Harju on 01/03/2017.
//  Copyright © 2017 Mapbox. All rights reserved.
//

import UIKit

import Mapbox

class ViewController: UIViewController {

    let tileLoader = MGLTileLoader()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        tileLoader.updateTiles()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func renderPressed(_ sender: Any) {
        tileLoader.render()
    }

}

