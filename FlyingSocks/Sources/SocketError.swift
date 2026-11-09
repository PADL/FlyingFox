//
//  SocketError.swift
//  FlyingFox
//
//  Created by Simon Whitty on 19/02/2022.
//  Copyright © 2022 Simon Whitty. All rights reserved.
//
//  Distributed under the permissive MIT license
//  Get the latest version from here:
//
//  https://github.com/swhitty/FlyingFox
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(Android)
import Android
#elseif canImport(Glibc) || canImport(Musl) || canImport(Bionic)
#if canImport(Musl)
import Musl
#elseif canImport(Bionic)
import Android
#else
import Glibc
#endif
#endif

public enum SocketError: LocalizedError, Equatable {
    case failed(type: String, errno: Int32, message: String)
    case blocked
    case disconnected
    case unsupportedAddress
    case timeout(message: String)

    public var errorDescription: String? {
        switch self {
        case .failed(let type, let errno, let message):
            return "SocketError. \(type)(\(errno)): \(message)"
        case .blocked:
            return "SocketError. Blocked"
        case .disconnected:
            return "SocketError. Disconnected"
        case .unsupportedAddress:
            return "SocketError. UnsupportedAddress"
        case .timeout(message: let message):
            return "SocketError. Timeout: \(message)"
        }
    }

    public static func makeFailed(_ type: StaticString) -> Self {
        .failed(type: String(describing: type),
                errno: errno,
                message: String(cString: strerror(errno)))
    }
}

extension SocketError {

    /// A failed accept(2) that leaves the listening socket usable: the next accept may succeed.
    var isTransientAcceptError: Bool {
        guard case .failed(let type, let errno, _) = self, type == "Accept" else { return false }
        return Self.transientAcceptErrors.contains(errno)
    }

    /// A transient accept failure for want of descriptors or memory, which accepting again at
    /// once would only repeat.
    var isResourceShortage: Bool {
        guard case .failed(_, let errno, _) = self else { return false }
        return [EMFILE, ENFILE, ENOBUFS, ENOMEM].contains(errno)
    }

    // accept(2): a connection aborted or failed before it was accepted, a signal, or a
    // shortage of descriptors or memory; on Linux, pending network errors are also reported
    // by accept and are to be treated like EAGAIN
    private static var transientAcceptErrors: Set<Int32> {
        var errors: Set<Int32> = [ECONNABORTED, EINTR, EMFILE, ENFILE, ENOBUFS, ENOMEM]
        #if !canImport(WinSDK)
        errors.formUnion([EPROTO, ENETDOWN, ENETUNREACH, EHOSTDOWN, EHOSTUNREACH, ENOPROTOOPT, EOPNOTSUPP])
        #endif
        return errors
    }
}
