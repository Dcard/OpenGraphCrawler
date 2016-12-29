//
//  OpenGraphCrawler.swift
//  Article
//
//  Created by Hsing-Yu, Su on 8/24/16.
//  Copyright © 2016 Dcard Taiwan, Ltd. All rights reserved.
//

import Foundation
import Alamofire
import Fuzi
import SQLite


public struct OpenGraphData {
    
    public let title : String?
    public let description : String?
    public let imageURL : String?
}


public typealias OpenGraphOperationCallback = (OpenGraphData?) -> ()
open class OpenGraphOperation {
    
    open let url : String
    open let callback : OpenGraphOperationCallback?
    
    public init(url: String, callback: OpenGraphOperationCallback?) {
        
        self.url = url
        self.callback = callback
    }
}


open class OpenGraphCrawler {
    
    // MARK: - Singleton
    open static let shared : OpenGraphCrawler = {
        
        let crawler = OpenGraphCrawler()
        
        // Target data paths
        crawler.titleSearchPaths = [
            ("//head/meta[@property='og:title']", "content")
        ]
        crawler.imageSearchPaths = [
            ("//head/meta[@property='og:image']", "content"),
            ("//head/link[@rel='apple-touch-icon']", "href"),
            ("//head/link[@rel='apple-touch-icon-precomposed']", "href"),
            ("//head/link[@rel='icon']", "href"),
            ("//head/link[@rel='shortcut icon']", "href")
        ]
        crawler.descriptionSearchPaths = [
            ("//head/meta[@property='og:description']", "content")
        ]
        
        return crawler
    }()
    
    // MARK: - SQLite Settings
    let db : Connection?
    let openGraphs    = Table("openGraphs")
    let dbURL         = Expression<String>("url")
    let dbTitle       = Expression<String?>("title")
    let dbDescription = Expression<String?>("description")
    let dbImageURL    = Expression<String?>("imageURL")
    
    // MARK: - Properties
    open var operations = [OpenGraphOperation]()
    let operationQueue = DispatchQueue(label: "com.asyncarticlekit.og", attributes: [])
    let dbQueue = DispatchQueue(label: "com.asyncarticlekit.db", attributes: [])
    
    typealias SearchPath = (elementPath: String, attribute: String)
    var titleSearchPaths = [SearchPath]()
    var imageSearchPaths = [SearchPath]()
    var descriptionSearchPaths = [SearchPath]()
    
    var maximumConcurrentWork = 3
    fileprivate(set) var workingCount = 0
    
    
    // MARK: - Life Cycle
    public init() {
        
        let path = NSSearchPathForDirectoriesInDomains(
            .documentDirectory, .userDomainMask, true
            ).first!
        
        self.db = try? Connection("\(path)/db.sqlite3")
        
        let _ = try? self.db?.run(self.openGraphs.create { t in
            t.column(self.dbURL, primaryKey: true)
            t.column(self.dbTitle)
            t.column(self.dbDescription)
            t.column(self.dbImageURL)
        })
        
        self.db?.busyHandler({ tries in
            if tries >= 3 {
                return false
            }
            return true
        })
    }
    
    
    // MARK: - Methods
    open func openGraphDataWithURL(_ urlString: String, callback: @escaping OpenGraphOperationCallback) {
        
        self.operationQueue.async {
            
            let operation = OpenGraphOperation(url: urlString, callback: callback)
            if !self.useCacheIfExist(operation) {
                self.operations.append(operation)
                self.doNextOperation()
            }
        }
    }
    
    open func doNextOperation() {
        
        self.operationQueue.async {
            
            if let operation = self.operations.first
                , self.workingCount < 3 {
                
                self.operations.removeFirst()
                self.doOperation(operation)
            }
        }
    }
    
    private func useCacheIfExist(_ operation: OpenGraphOperation) -> Bool {
        
        var ogData : OpenGraphData?
        
        let semaphore = DispatchSemaphore(value: 0)
        self.dbQueue.async {
            if  let db  = self.db,
                let ogs = try? db.prepare(
                    self.openGraphs.select(self.dbTitle, self.dbDescription, self.dbImageURL).filter(self.dbURL == operation.url)) {
                
                for og in ogs {
                    ogData = OpenGraphData(title: og[self.dbTitle], description: og[self.dbDescription], imageURL: og[self.dbImageURL])
                    break
                }
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: DispatchTime.distantFuture)
        
        if let ogData = ogData {
            DispatchQueue.global(qos: .default).async {
                operation.callback?(ogData)
            }
            return true
        }
        return false
    }
    
    private func doOperation(_ operation: OpenGraphOperation) {
        
        self.workingCount += 1
        DispatchQueue.global().async {
            
            let semaphore = DispatchSemaphore(value: 0)
            let urlString = operation.url
            var ogData : OpenGraphData?
            
            Alamofire.request(urlString)
                .response(queue: DispatchQueue.global())
                { [weak self] (response) in
                    
                    defer {
                        semaphore.signal()
                    }
                    
                    guard let `self` = self else {return}
                    guard response.error == nil else {return}
                    
                    if  response.data != nil {
                        
                        var doc : HTMLDocument?
                        autoreleasepool {
                            doc = try? HTMLDocument(data: response.data!)
                        }
                        
                        var title : String?
                        var describe : String?
                        var imageURL : String?
                        if doc != nil {
                            
                            // Fetch Title
                            autoreleasepool {
                                
                                for searchPath in self.titleSearchPaths {
                                    title = doc!.xpath(searchPath.elementPath).first?[searchPath.attribute]
                                    if title != nil {
                                        break
                                    }
                                }
                                
                                if  title == nil,
                                    let htmlTitle = doc!.xpath("//title").first?.stringValue,
                                    htmlTitle.characters.count > 0 {
                                    title = htmlTitle
                                }
                                title = title?.replacingOccurrences(of: "\n", with: " ")
                            }
                            
                            // Fetch Image
                            autoreleasepool {
                                
                                for searchPath in self.imageSearchPaths {
                                    imageURL = doc!.xpath(searchPath.elementPath).first?[searchPath.attribute]
                                    if imageURL != nil {
                                        break
                                    }
                                }
                                
                                if let url = imageURL {
                                    if url.hasPrefix("//") {
                                        imageURL = "http:" + url
                                    } else if url.hasPrefix("/") {
                                        
                                        if  let rootURL = NSURL(string: urlString),
                                            let host = rootURL.host {
                                            imageURL = "http://" + host + url
                                        }
                                    }
                                }
                            }
                            
                            // Fetch Description
                            autoreleasepool {
                                for searchPath in self.descriptionSearchPaths {
                                    describe = doc!.xpath(searchPath.elementPath).first?[searchPath.attribute]
                                    if describe != nil {
                                        break
                                    }
                                }
                            }
                        }
                        doc = nil
                        
                        ogData = OpenGraphData(
                            title: title,
                            description: describe,
                            imageURL: imageURL
                        )
                        
                        self.dbQueue.async {
                            let insert = self.openGraphs.insert(
                                self.dbURL <- urlString,
                                self.dbTitle <- ogData?.title,
                                self.dbDescription <- ogData?.description,
                                self.dbImageURL <- ogData?.imageURL
                            )
                            let _ = try? self.db?.run(insert)
                        }
                    }
            }
            _ = semaphore.wait(timeout: DispatchTime.distantFuture)
            
            operation.callback?(ogData)
            self.workingCount -= 1
            self.doNextOperation()
        }
    }
}










