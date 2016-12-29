//
//  ViewController.swift
//  OpenGraphCrawler
//
//  Created by aipeople on 27/12/2016.
//  Copyright © 2016 dcard. All rights reserved.
//

import UIKit
import SDWebImage

class ViewController: UIViewController {

    @IBOutlet var urlField   : UITextField!
    @IBOutlet var imageView  : UIImageView!
    @IBOutlet var titleLabel : UILabel!
    @IBOutlet var textLabel  : UILabel!
    @IBOutlet var indicator  : UIActivityIndicatorView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.urlField.becomeFirstResponder()
        self.urlField.delegate = self
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}

extension ViewController : UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        
        self.view.isUserInteractionEnabled = false
        self.imageView.isHidden  = true
        self.titleLabel.isHidden = true
        self.textLabel.isHidden  = true
        self.indicator.startAnimating()
        
        OpenGraphCrawler.shared.openGraphDataWithURL(textField.text ?? "") {(data) in
            
            DispatchQueue.main.async {
                
                if  let url = URL(string:  data?.imageURL ?? "") {
                    self.imageView.sd_setImage(with:url)
                }
                self.titleLabel.text = data?.title
                self.textLabel.text  = data?.description
                self.view.isUserInteractionEnabled = true
                self.imageView.isHidden  = false
                self.titleLabel.isHidden = false
                self.textLabel.isHidden  = false
                self.indicator.stopAnimating()
            }
        }
        
        return false
    }
}

