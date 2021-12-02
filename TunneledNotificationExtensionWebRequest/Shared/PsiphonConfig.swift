//
//  PsiphonConfig.swift
//  TunneledNotificationExtensionWebRequest
/*
 Licensed under Creative Commons Zero (CC0).
 https://creativecommons.org/publicdomain/zero/1.0/
 */

import Foundation

// Defined in project settings under "App Groups" capability.
let appGroupIdentifier = "group.com.psiphon3.ios.TunneledNotificationExtensionWebRequest"

// Data root directory to be used by PsiphonTunnel.
// Creates the directory if it doesn't already exist.
func getPsiphonDataRootDirectory() throws -> URL {
    
    let url = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
        .appendingPathComponent("com.psiphon3.ios.PsiphonTunnel")
    
    guard let url = url else {
        throw ErrorMessage("Failed to get path to App Group container")
    }
    
    try FileManager.default.createDirectory(at: url,
                                        withIntermediateDirectories: true,
                                        attributes: [:])
    
    return url
    
}

// Loads `psiphon-config.json` file form the main bundle, and sets `DataRootDirectory` key.
func loadPsiphonConfig(dataRootDirectory: String) throws -> [String: Any] {
    
    guard
        let psiphonConfigUrl = Bundle.main.url(forResource: "psiphon-config", withExtension: "json")
    else {
        throw ErrorMessage("Error getting Psiphon config resource file URL!")
    }
    
    guard
        let jsonData = FileManager.default.contents(atPath: psiphonConfigUrl.path)
    else {
        throw ErrorMessage("Failed to read psiphon config file")
    }
    
    do {
        
        // De-serializes the config JSON object, and adds "DataRootDirectory" key.
        var config = try JSONSerialization.jsonObject(with: jsonData, options: []) as! [String: Any]
        config["DataRootDirectory"] = dataRootDirectory
        return config
        
    } catch {
        throw ErrorMessage("Error reading Psiphon config resource file!")
    }
    
}

// Loads `psiphon-embedded-server-entries.txt` file from the main bundle.
func loadEmbeddedServerEntries() -> String? {
    
    guard let psiphonEmbeddedServerEntriesUrl = Bundle.main.url(forResource: "psiphon-embedded-server-entries", withExtension: "txt") else {
        NSLog("Error getting Psiphon embedded server entries resource file URL!")
        return nil
    }

    do {
        return try String(contentsOf: psiphonEmbeddedServerEntriesUrl)
    } catch {
        NSLog("Error reading Psiphon embedded server entries resource file!")
        return nil
    }
    
}
