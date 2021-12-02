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
//            if buffer == nil {
//                let success = allocateMemory(numberOfBytes: 10_000_000 /* 9 MB */)
//                guard success else {
//                    displayNotification("Failed to allocate memory")
//                    return
//                }
//                NSLog("**Reserved memory")
//            } else {
//                NSLog("**Did not reserve memory")
//            }
            
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


// MARK: TunneledAppDelegate implementation
// See the protocol definition for details about the methods.
// Note that we're excluding all the optional methods that we aren't using,
// however your needs may be different.
extension NotificationService: TunneledAppDelegate {
    
    func getPsiphonConfig() -> Any? {
        
        do {
            
            let dataRootDir = try getPsiphonDataRootDirectory()
            return try loadPsiphonConfig(dataRootDirectory:dataRootDir.path)
            
        } catch {
            NSLog("Failed to get Psiphon config: \(error)")
            return nil
        }
        
    }

    /// Read the Psiphon embedded server entries resource file and return the contents.
    /// * returns: The string of the contents of the file.
    func getEmbeddedServerEntries() -> String? {
        loadEmbeddedServerEntries()
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
            makeRequestViaUrlProxy(self.httpProxyPort, url) { [weak self]
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
