//
//  Requests.swift
//  TunneledNotificationExtensionWebRequest
/*
 Licensed under Creative Commons Zero (CC0).
 https://creativecommons.org/publicdomain/zero/1.0/
 */

import Foundation

/// Request URL using URLSession configured to use the current proxy.
/// - Parameters:
///   - socksProxyPort: Socks proxy port opened by PsiphonTunnel
///   - url: The URL to request.
///   - completion: A callback function that will received the string obtained
///     from the request, or nil if there's an error.
/// - Returns: The string obtained from the request, or nil if there's an error.
func makeRequestViaUrlSessionProxy(
    _ socksProxyPort: Int,
    _ url: String,
    completion: @escaping (_ result: String?, _ error: String?) -> ()
) {
    
    assert(socksProxyPort > 0)
    
    let request = URLRequest(url: URL(string: url)!)
    
    let config = URLSessionConfiguration.ephemeral
    config.requestCachePolicy = URLRequest.CachePolicy.reloadIgnoringLocalCacheData
    config.connectionProxyDictionary = [AnyHashable: Any]()
    config.timeoutIntervalForRequest = 60 * 5
    
    // Enable and set the SOCKS proxy values.
    config.connectionProxyDictionary?[kCFStreamPropertySOCKSProxy as String] = 1
    config.connectionProxyDictionary?[kCFStreamPropertySOCKSProxyHost as String] = "127.0.0.1"
    config.connectionProxyDictionary?[kCFStreamPropertySOCKSProxyPort as String] = socksProxyPort
    
    // Alternatively, the HTTP proxy can be used. Below are the settings for that.
    // The HTTPS key constants are mismatched and Xcode gives deprecation warnings, but they seem to be necessary to proxy HTTPS requests. This is probably a bug on Apple's side; see: https://forums.developer.apple.com/thread/19356#131446
    // config.connectionProxyDictionary?[kCFNetworkProxiesHTTPEnable as String] = 1
    // config.connectionProxyDictionary?[kCFNetworkProxiesHTTPProxy as String] = "127.0.0.1"
    // config.connectionProxyDictionary?[kCFNetworkProxiesHTTPPort as String] = self.httpProxyPort
    // config.connectionProxyDictionary?[kCFStreamPropertyHTTPSProxyHost as String] = "127.0.0.1"
    // config.connectionProxyDictionary?[kCFStreamPropertyHTTPSProxyPort as String] = self.httpProxyPort
    
    let session = URLSession(configuration: config)
    
    // Create the URLSession task that will make the request via the tunnel proxy.
    let task = session.dataTask(with: request) {
        (data: Data?, response: URLResponse?, error: Error?) in
        if error != nil {
            let errorString = "Client-side error in request to \(url): \(String(describing: error))"
            NSLog(errorString)
            // Invoke the callback indicating error.
            completion(nil, errorString)
            return
        }
        
        if data == nil {
            let errorString = "Data from request to \(url) is nil"
            NSLog(errorString)
            // Invoke the callback indicating error.
            completion(nil, errorString)
            return
        }
        
        let httpResponse = response as? HTTPURLResponse
        if httpResponse?.statusCode != 200 {
            let errorString = "Server-side error in request to \(url): \(String(describing: httpResponse))"
            NSLog(errorString)
            // Invoke the callback indicating error.
            completion(nil, errorString)
            return
        }
        
        let encodingName = response?.textEncodingName != nil ? response?.textEncodingName : "utf-8"
        let encoding = CFStringConvertEncodingToNSStringEncoding(CFStringConvertIANACharSetNameToEncoding(encodingName as CFString?))
        
        let stringData = String(data: data!, encoding: String.Encoding(rawValue: UInt(encoding)))
        
        // Make sure the session is cleaned up.
        session.invalidateAndCancel()
        
        // Invoke the callback with the result.
        completion(stringData, nil)
    }
    
    // Start the request task.
    task.resume()
    
}

/// Request URL using Psiphon's "URL proxy" mode.
/// For details, see the comment near the top of:
/// https://github.com/Psiphon-Labs/psiphon-tunnel-core/blob/master/psiphon/httpProxy.go
/// - Parameters:
///   - httpProxyPort: HTTP proxy port opened by PsiphonTunnel.
///   - url: The URL to request.
///   - completion: A callback function that will received the string obtained
///     from the request, or nil if there's an error.
/// - Returns: The string obtained from the request, or nil if there's an error.
func makeRequestViaUrlProxy(
    _ httpProxyPort: Int,
    _ url: String,
    completion: @escaping (_ result: String?, _ error: String?) -> ()
) {
    
    assert(httpProxyPort > 0)
    
    // The target URL must be encoded so as to be valid within a query parameter.
    let encodedTargetURL = url.URLEncoded
    
    let proxiedURL = "http://127.0.0.1:\(httpProxyPort)/tunneled/\(encodedTargetURL)"
    
    let task = URLSession.shared.dataTask(with: URL(string: proxiedURL)!) {
        (data: Data?, response: URLResponse?, error: Error?) in
        if error != nil {
            let errorString = "Client-side error in request to \(url): \(String(describing: error))"
            NSLog(errorString)
            // Invoke the callback indicating error.
            completion(nil, errorString)
            return
        }
        
        if data == nil {
            let errorString = "Data from request to \(url) is nil"
            NSLog(errorString)
            // Invoke the callback indicating error.
            completion(nil, errorString)
            return
        }
        
        let httpResponse = response as? HTTPURLResponse
        if httpResponse?.statusCode != 200 {
            let errorString = "Server-side error in request to \(url): \(String(describing: httpResponse))"
            NSLog(errorString)
            // Invoke the callback indicating error.
            completion(nil, errorString)
            return
        }
        
        let encodingName = response?.textEncodingName != nil ? response?.textEncodingName : "utf-8"
        let encoding = CFStringConvertEncodingToNSStringEncoding(CFStringConvertIANACharSetNameToEncoding(encodingName as CFString?))
        
        let stringData = String(data: data!, encoding: String.Encoding(rawValue: UInt(encoding)))
        
        // Invoke the callback with the result.
        completion(stringData, nil)
    }
    
    // Start the request task.
    task.resume()
    
}
