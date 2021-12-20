//
//  ImageRecognitionHelper.swift
//  HSTracker
//
//  Created by AO on 19.12.21.
//  Copyright © 2021 Benjamin Michotte. All rights reserved.
//

import Foundation
import WebKit
import Vision
import UniformTypeIdentifiers

enum MapLevelType: String {
    case protectorBattle, casterBattle, fighterBattle, eliteFighterBattle, eliteCasterBattle, eliteProtectorBattle, boonCaters, boonProtectors, boonFighters, spiritHealer, mystery, invalid
    
    init(string: String) {
        self.init(rawValue: MapLevelType.closestStringTo(string).camelized)!
    }
    
    static func closestStringTo(_ string: String) -> String {
        return MapLevelType.allTypes.first(where: { jaroWinkler($0, string) > 0.8 }) ?? "invalid"
    }
    
    static let allTypes = ["Protector Battle",
                           "Caster Battle",
                           "Fighter Battle",
                           "Elite Fighter Battle",
                           "Elite Caster Battle",
                           "Elite Protector Battle",
                           "Boon: Fighters",
                           "Boon: Casters",
                           "Boon: Protectors",
                           "Mystery",
                           "Spirit Healer"]
}

class ImageRecognitionHelper {
    
    static var windowID: CGWindowID? {
        return (NSPoint.hsInfo?[(kCGWindowNumber as String)] as? NSNumber)?.uint32Value
    }
    
    class func makeScreenshot(position: NSPoint, completion: @escaping (([String])->Void)) {
        let side = NSPoint.frame.size.height / 4
        
        let rect = NSRect(x: 0, y: position.y - side / 2, width: NSPoint.frame.size.width, height: side)
        
        recognizeTextIn(rect: rect, completion: completion)
    }
    
    class func recognizeTextIn(rect: NSRect, completion: @escaping (([String])->Void)) {
        if let windowImage: CGImage = CGWindowListCreateImage(rect,
                                                              .optionIncludingWindow,
                                                              windowID ?? 0,
                                                              [.boundsIgnoreFraming,
                                                               .nominalResolution]) {
            let image = NSImage(cgImage: windowImage, size: rect.size)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            
            let requestHandler = VNImageRequestHandler(cgImage: windowImage)
            
            // Create a new request to recognize text.
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
                let recognizedStrings = observations.compactMap { $0.topCandidates(1).first?.string }
                
                DispatchQueue.main.async {
                    completion(recognizedStrings)
                }
            }
            
            do {
                try requestHandler.perform([request])
            } catch {
                print("Unable to perform the requests: \(error).")
            }
        }
    }
    
    class func analyzeReadyButton(completion: @escaping (([String])->Void)) {
        let height = NSPoint.frame.height
        let width = NSPoint.frame.width
        let x = NSPoint.frame.origin.x + width / 3 * 2
        let y = NSPoint.frame.origin.y
        
        recognizeTextIn(rect: NSRect(x: x, y: y, width: width, height: height), completion: completion)
    }
}

func jaroDistance(_ s1: String, _ s2: String) -> Double {
    // If the strings are equal
    //if s1 == s2 {
    //    return 1.0
    //}
    
    // Length of two strings
    let len1 = s1.count,
        len2 = s2.count
    //
    if len1 == 0 || len2 == 0 {
        return 0.0
    }
    
    // Maximum distance upto which matching
    // is allowed
    let maxDist = max(len1, len2) / 2 - 1
    
    // Count of matches
    var match = 0
    
    // Hash for matches
    var hashS1: [Int] = Array(repeating: 0, count: s1.count)
    var hashS2: [Int] = Array(repeating: 0, count: s2.count)
    
    let s2Array = Array(s2)
    // Traverse through the first string
    for (i, ch1) in s1.enumerated() {
        
        // Check if there is any matches
        if max(0, i - maxDist) > min(len2 - 1, i + maxDist) {
            continue
        }
        for j in max(0, i - maxDist)...min(len2 - 1, i + maxDist) {
            
            // If there is a match
            if ch1 == s2Array[j] &&
                hashS2[j] == 0 {
                hashS1[i] = 1
                hashS2[j] = 1
                match += 1
                break
            }
        }
    }
    
    // If there is no match
    if match == 0 {
        return 0.0
    }
    
    // Number of transpositions
    var t: Double = 0
    
    var point = 0
    
    // Count number of occurances
    // where two characters match but
    // there is a third matched character
    // in between the indices
    for (i, ch1) in s1.enumerated() {
        if hashS1[i] == 1 {
            
            // Find the next matched character
            // in second string
            while hashS2[point] == 0 {
                point += 1
            }
            
            if ch1 != s2Array[point] {
                t += 1
            }
            point += 1
        }
    }
    t /= 2
    print(s1.count, s2.count, match, t)
    
    // Return the Jaro Similarity
    return (Double(match) / Double(len1)
                + Double(match) / Double(len2)
                + (Double(match) - t) / Double(match))
        / 3.0
}
// Jaro Winkler Similarity
func jaroWinkler(_ s1: String, _ s2: String) -> Double {
    var jaroDist = jaroDistance(s1, s2)
    print("Jaro Similarity =", jaroDist)
    
    // If the jaro Similarity is above a threshold
    if jaroDist > 0.7 {
        
        // Find the length of common prefix
        let prefixStr = s1.commonPrefix(with: s2)
        
        // Maximum of 4 characters are allowed in prefix
        let prefix = Double(min(4, prefixStr.count))
        
        // Calculate jaro winkler Similarity
        jaroDist += 0.1 * prefix * (1 - jaroDist)
    }
    return jaroDist
}
