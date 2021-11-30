//
//  NotificationService.swift
//  NotificationExtension
/*
 Licensed under Creative Commons Zero (CC0).
 https://creativecommons.org/publicdomain/zero/1.0/
 */


import UserNotifications

import PsiphonTunnel

var buffer: [UInt8]? = nil

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    var socksProxyPort: Int = 0
    var httpProxyPort: Int = 0

    // The instance of PsiphonTunnel we'll use for connecting.
    var psiphonTunnel: PsiphonTunnel?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        if let bestAttemptContent = bestAttemptContent {
            // Modify the notification content here...
            bestAttemptContent.title = "\(bestAttemptContent.title) [modified]"
            
            // Reserves memory to simulate memory used by actual application
            if buffer == nil {
                let success = allocateMemory(numberOfBytes: 10_000_000 /* 9 MB */)
                guard success else {
                    displayNotification("Failed to allocate memory")
                    return
                }
                NSLog("**Reserved memory")
            } else {
                NSLog("**Did not reserve memory")
            }
            
            psiphonTunnel = PsiphonTunnel.newPsiphonTunnel(self)

            // Start up the tunnel and begin connecting.
            // This could be started elsewhere or earlier.
            NSLog("Starting tunnel")

            guard let success = psiphonTunnel?.start(true), success else {
                displayNotification("psiphonTunnel.start returned false")
                return
            }

            // The Psiphon Library exposes reachability functions, which can be used for detecting internet status.
            let reachability = Reachability.forInternetConnection()
            let networkStatus = reachability?.currentReachabilityStatus()
            NSLog("Internet is reachable? \(networkStatus != NotReachable)")

        }
    }

    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        self.psiphonTunnel?.stop()
        if let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent {
            bestAttemptContent.title = "\(bestAttemptContent.title) [time expired]"
            contentHandler(bestAttemptContent)
        }
    }

    // Stops tunnel and displays notification with the given body.
    func displayNotification(_ body: String) {
        psiphonTunnel?.stop()
        bestAttemptContent!.body = "\(body) [display notif]"
        contentHandler!(bestAttemptContent!)
        exit(0) // We seem to be leaking memory somewhere, this is a sample app, so for now we'll just exit the process after processing the notification.
    }

    // Simulates memory used by the actual application by allocating `numberOfBytes` of memory.
    func allocateMemory(numberOfBytes: Int) -> Bool {
        
        // Note that actual memory is not allcoated here,
        // for performance reasons we write to the buffer at every page size
        // (instead of every byte).
        buffer = [UInt8](repeating: 0, count: numberOfBytes)
        
        var page_size = vm_size_t()
        let kerr: kern_return_t = host_page_size(mach_host_self(), &page_size)
        guard kerr == KERN_SUCCESS else {
            return false
        }
        
        for i in stride(from: 0, to: numberOfBytes, by: Int(page_size)) {
            buffer![i] = UInt8(i % 7)
        }
        
        return true
        
    }

}

extension NotificationService {

    /// Request URL using URLSession configured to use the current proxy.
    /// * parameters:
    ///   - url: The URL to request.
    ///   - completion: A callback function that will received the string obtained
    ///     from the request, or nil if there's an error.
    /// * returns: The string obtained from the request, or nil if there's an error.
    func makeRequestViaUrlSessionProxy(_ url: String, completion: @escaping (_ result: String?, _ error: String?) -> ()) {
        let socksProxyPort = self.socksProxyPort
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
    /// * parameters:
    ///   - url: The URL to request.
    ///   - completion: A callback function that will received the string obtained
    ///     from the request, or nil if there's an error.
    /// * returns: The string obtained from the request, or nil if there's an error.
    func makeRequestViaUrlProxy(_ url: String, completion: @escaping (_ result: String?, _ error: String?) -> ()) {
        let httpProxyPort = self.httpProxyPort
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
}

// MARK: TunneledAppDelegate implementation
// See the protocol definition for details about the methods.
// Note that we're excluding all the optional methods that we aren't using,
// however your needs may be different.
extension NotificationService: TunneledAppDelegate {
    func getPsiphonConfig() -> Any? {
        // In this example, we're going to retrieve our Psiphon config from a file in the app bundle.
        // Alternatively, it could be a string literal in the code, or whatever makes sense.

        guard let psiphonConfigUrl = Bundle.main.url(forResource: "psiphon-config", withExtension: "json") else {
            NSLog("Error getting Psiphon config resource file URL!")
            return nil
        }

        do {
            return try String.init(contentsOf: psiphonConfigUrl)
        } catch {
            NSLog("Error reading Psiphon config resource file!")
            return nil
        }
    }

    /// Read the Psiphon embedded server entries resource file and return the contents.
    /// * returns: The string of the contents of the file.
    func getEmbeddedServerEntries() -> String? {
        guard let psiphonEmbeddedServerEntriesUrl = Bundle.main.url(forResource: "psiphon-embedded-server-entries", withExtension: "txt") else {
            NSLog("Error getting Psiphon embedded server entries resource file URL!")
            return nil
        }

        do {
            return try String.init(contentsOf: psiphonEmbeddedServerEntriesUrl)
        } catch {
            NSLog("Error reading Psiphon embedded server entries resource file!")
            return nil
        }
    }

    func onDiagnosticMessage(_ message: String, withTimestamp timestamp: String) {
        NSLog("onDiagnosticMessage(%@): %@", timestamp, message)
    }

    func onConnected() {
        NSLog("onConnected")

        // After we're connected, make tunneled requests

        DispatchQueue.global(qos: .default).async {
            

            let url = "https://freegeoip.app/json/"

            // Makes a request using HTTP proxy
            self.makeRequestViaUrlProxy(url) { [weak self]
                (_ result: String?, _ error: String?) in

                guard let self = self else { return }

                if let error = error {

                    let errorString = error.replacingOccurrences(of: ",", with: ",\n  ")
                        .replacingOccurrences(of: "{", with: "{\n  ")
                        .replacingOccurrences(of: "}", with: "\n}")

                    DispatchQueue.main.sync {

                        self.displayNotification("""
                        Error from \(url):\n\n
                        \(errorString)\n\n
                        Using makeRequestViaUrlSessionProxy.\n\n
                        Check logs for error.
                        """)

                    }

                } else {

                    guard result != nil else {
                        DispatchQueue.main.sync {
                            self.displayNotification("Failed to get \(url)")
                        }
                        return
                    }

                    // Do a little pretty-printing.
                    let prettyResult = result?.replacingOccurrences(of: ",", with: ",\n  ")
                        .replacingOccurrences(of: "{", with: "{\n  ")
                        .replacingOccurrences(of: "}", with: "\n}")

                    DispatchQueue.main.sync {
                        self.displayNotification("Result from \(url):\n\(prettyResult!)")
                    }
                }

            }
        }
    }

    func onListeningSocksProxyPort(_ port: Int) {
        DispatchQueue.main.async {
            self.socksProxyPort = port
        }
    }

    func onListeningHttpProxyPort(_ port: Int) {
        DispatchQueue.main.async {
            self.httpProxyPort = port
        }
    }
}

extension String {
    
    // Encode all reserved characters. See: https://stackoverflow.com/a/34788364.
    //
    // From RFC 3986 (https://www.ietf.org/rfc/rfc3986.txt):
    //
    //   2.3.  Unreserved Characters
    //
    //   Characters that are allowed in a URI but do not have a reserved
    //   purpose are called unreserved.  These include uppercase and lowercase
    //   letters, decimal digits, hyphen, period, underscore, and tilde.
    //
    //   unreserved  = ALPHA / DIGIT / "-" / "." / "_" / "~"
    var URLEncoded:String {
        let unreservedChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        let unreservedCharsSet: CharacterSet = CharacterSet(charactersIn: unreservedChars)
        let encodedString = self.addingPercentEncoding(withAllowedCharacters: unreservedCharsSet)!
        return encodedString
    }
    
}
