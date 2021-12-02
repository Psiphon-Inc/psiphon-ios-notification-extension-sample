//
//  Utils.swift
//  TunneledNotificationExtensionWebRequest
/*
 Licensed under Creative Commons Zero (CC0).
 https://creativecommons.org/publicdomain/zero/1.0/
 */

import Foundation


struct ErrorMessage: Error {
    let message: String
    init(_ message: String) {
        self.message = message
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
