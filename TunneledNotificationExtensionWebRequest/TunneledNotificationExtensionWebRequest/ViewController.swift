//
//  ViewController.swift
//  TunneledWebView
//
/*
 Licensed under Creative Commons Zero (CC0).
 https://creativecommons.org/publicdomain/zero/1.0/
 */


import UIKit
import PsiphonTunnel

class ViewController: UIViewController {
    
    var socksProxyPort: Int = 0
    var httpProxyPort: Int = 0

    // The instance of PsiphonTunnel we'll use for connecting.
    var psiphonTunnel: PsiphonTunnel?

    @IBOutlet weak var resultLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    @IBAction func connectAndMakeRequest(_ sender: UIButton) {
        
        guard psiphonTunnel == nil else {
            NSLog("Tunnel is already active")
            return
        }
        
        self.resultLabel.text = "..."
        
        psiphonTunnel = PsiphonTunnel.newPsiphonTunnel(self)

        // Start up the tunnel and begin connecting.
        // This could be started elsewhere or earlier.
        NSLog("Starting tunnel")

        guard let success = psiphonTunnel?.start(true), success else {
            NSLog("psiphonTunnel.start returned false")
            return
        }

        // The Psiphon Library exposes reachability functions, which can be used for detecting internet status.
        let reachability = Reachability.forInternetConnection()
        let networkStatus = reachability?.currentReachabilityStatus()
        NSLog("Internet is reachable? \(networkStatus != NotReachable)")
        
    }

}

// MARK: TunneledAppDelegate implementation
// See the protocol definition for details about the methods.
// Note that we're excluding all the optional methods that we aren't using,
// however your needs may be different.
extension ViewController: TunneledAppDelegate {
    
    func getPsiphonConfig() -> Any? {
        
        do {
            
            let dataRootDir = try getPsiphonDataRootDirectory()
            
            NSLog("Psiphon DataRootDirectory: \(dataRootDir)")
            
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
                
                // Clean up after the request is finished
                defer {
                    DispatchQueue.main.async {
                        self.psiphonTunnel?.stop()
                        self.psiphonTunnel = nil
                    }
                }

                if let error = error {

                    let errorString = error.replacingOccurrences(of: ",", with: ",\n  ")
                        .replacingOccurrences(of: "{", with: "{\n  ")
                        .replacingOccurrences(of: "}", with: "\n}")

                    DispatchQueue.main.sync {

                        self.resultLabel.text = """
                        Error from \(url):\n\n
                        \(errorString)\n\n
                        Using makeRequestViaUrlSessionProxy.\n\n
                        Check logs for error.
                        """
                        
                    }

                } else {

                    guard result != nil else {
                        DispatchQueue.main.sync {
                            self.resultLabel.text = "Failed to get \(url)"
                        }
                        return
                    }

                    // Do a little pretty-printing.
                    let prettyResult = result?.replacingOccurrences(of: ",", with: ",\n  ")
                        .replacingOccurrences(of: "{", with: "{\n  ")
                        .replacingOccurrences(of: "}", with: "\n}")

                    // TODO!! is there a reason these function sare async
                    DispatchQueue.main.sync {
                        self.resultLabel.text = "Result from \(url):\n\(prettyResult!)"
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
