//
//  SocketPool+ePoll.swift
//  FlyingFox
//
//  Created by Simon Whitty on 30/08/2022.
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

#if canImport(CSystemLinux)
import CSystemLinux

public extension AsyncSocketPool where Self == SocketPool<ePoll> {
    static func ePoll(maxEvents limit: Int = 20, logger: some Logging = .disabled) -> SocketPool<ePoll> {
        .init(maxEvents: limit, logger: logger)
    }

    private init(maxEvents limit: Int, logger: some Logging = .disabled) {
        self.init(queue: FlyingSocks.ePoll(maxEvents: limit, logger: logger), logger: logger)
    }
}

public struct ePoll: EventQueue {

    private(set) var file: Socket.FileDescriptor
    private(set) var canary: Socket.FileDescriptor
    private(set) var existing: [Socket.FileDescriptor: Socket.Events]
    private let eventsLimit: Int
    private let logger: any Logging

    public init(maxEvents limit: Int, logger: some Logging = .disabled) {
        self.file = .invalid
        self.canary = .invalid
        self.existing = [:]
        self.eventsLimit = limit
        self.logger = logger
    }

    public mutating func open() throws {
        existing = [:]
        self.file = try Self.makeQueue()
        self.canary = try Self.makeEventTrigger()

        var event = CSystemLinux.epoll_event()
        let options: EPOLLEvents = [EPOLLEvents.edgeTriggered, EPOLLEvents.read]
        event.events = options.rawValue
        event.data.fd = canary.rawValue
        guard epoll_ctl(file.rawValue, EPOLL_CTL_ADD, canary.rawValue, &event) != -1 else {
            throw SocketError.makeFailed("epoll_ctl EPOLL_CTL_ADD")
        }
    }

    public mutating func stop() throws {
        existing = [:]
        guard canary != .invalid else {
            throw SocketError.disconnected
        }
        eventfd_write(canary.rawValue, 1);
        canary = .invalid

    }

    public mutating func close() throws {
        guard file != .invalid else {
            throw SocketError.disconnected
        }
        defer { file = .invalid }
        try Self.closeQueue(file: file)
    }

    public mutating func addEvents(_ events: Socket.Events, for socket: Socket.FileDescriptor) throws {
        var socketEvents = existing[socket] ?? []
        socketEvents.formUnion(events)
        try setEvents(socketEvents, for: socket)
    }

    public mutating func removeEvents(_ events: Socket.Events, for socket: Socket.FileDescriptor) throws {
        var socketEvents = existing[socket] ?? []
        for evt in events {
            socketEvents.remove(evt)
        }
        try setEvents(socketEvents, for: socket)
    }

    mutating func setEvents(_ events: Socket.Events, for socket: Socket.FileDescriptor) throws {
        var event = CSystemLinux.epoll_event()
        event.events = events.epollEvents.rawValue
        event.data.fd = socket.rawValue

        if existing[socket] != nil {
            if events.isEmpty {
                guard epoll_ctl(file.rawValue, EPOLL_CTL_DEL, socket.rawValue, &event) != -1 else {
                    throw SocketError.makeFailed("epoll_ctl EPOLL_CTL_DEL")
                }
            } else {
                guard epoll_ctl(file.rawValue, EPOLL_CTL_MOD, socket.rawValue, &event) != -1 else {
                    throw SocketError.makeFailed("epoll_ctl EPOLL_CTL_MOD")
                }
            }
        } else if !events.isEmpty {
            guard epoll_ctl(file.rawValue, EPOLL_CTL_ADD, socket.rawValue, &event) != -1 else {
                throw SocketError.makeFailed("epoll_ctl EPOLL_CTL_ADD")
            }
        }

        if events.isEmpty {
            existing[socket] = nil
        } else {
            existing[socket] = events
        }
    }

    public func getNotifications() throws -> [EventNotification] {
        guard canary != .invalid else {
            throw SocketError.disconnected
        }
        var events = Array(repeating: epoll_event(), count: eventsLimit)
        let status = CSystemLinux.epoll_wait(file.rawValue, &events, Int32(eventsLimit), -1)
        guard status > 0 else {
            throw SocketError.makeFailed("epoll wait")
        }

        return try events
            .prefix(Int(status))
            .map(makeNotification)
    }

    func makeNotification(from event: epoll_event) throws -> EventNotification {
        var notification = EventNotification.make(from: event)
        if notification.events.isEmpty, let existing = existing[notification.file] {
            notification.events = existing
        }

        if event.data.fd == self.canary.rawValue {
            throw SocketError.disconnected
        }
        return notification
    }

    static func makeQueue(file: Int32 = CSystemLinux.epoll_create1(0)) throws -> Socket.FileDescriptor {
        let file = Socket.FileDescriptor(rawValue: file)
        guard file != .invalid else {
            throw SocketError.makeFailed("epoll")
        }
        return file
    }

    static func makeEventTrigger(file: Int32 = CSystemLinux.eventfd(0, Int32(EFD_NONBLOCK))) throws -> Socket.FileDescriptor {
        let file = Socket.FileDescriptor(rawValue: file)
        guard file != .invalid else {
            throw SocketError.makeFailed("eventfd")
        }
        return file
    }

    static func closeQueue(file: Socket.FileDescriptor) throws {
        guard file != .invalid else { return }
        guard Socket.close(file.rawValue) >= 0 else {
            throw SocketError.makeFailed("epoll")
        }
    }
}

extension EventNotification {

    static func make(from event: epoll_event) -> Self {
        let pollEvents = EPOLLEvents(rawValue: event.events)

        var events = Socket.Events()
        if pollEvents.contains(.read) {
            events.insert(.read)
        }
        if pollEvents.contains(.write) {
            events.insert(.write)
        }

        var notification = EventNotification(
            file: .init(rawValue: event.data.fd),
            events: events,
            errors: []
        )

        if !pollEvents.contains(.read) {
            if pollEvents.contains(.hup) || pollEvents.contains(.rdhup) {
                notification.errors.insert(.endOfFile)
            }
        }

        if pollEvents.contains(.err) || pollEvents.contains(.pri) {
            notification.errors.insert(.error)
        }

        return notification
    }
}

private struct EPOLLEvents: OptionSet, Hashable {
    var rawValue: UInt32

#if canImport(Musl)
    static let read = EPOLLEvents(rawValue: UInt32(EPOLLIN))
    static let write = EPOLLEvents(rawValue: UInt32(EPOLLOUT))
    static let hup = EPOLLEvents(rawValue: UInt32(EPOLLHUP))
    static let rdhup = EPOLLEvents(rawValue: UInt32(EPOLLRDHUP))
    static let err = EPOLLEvents(rawValue: UInt32(EPOLLERR))
    static let pri = EPOLLEvents(rawValue: UInt32(EPOLLPRI))
    static let edgeTriggered = EPOLLEvents(rawValue: UInt32(EPOLLET))
#else
    static let read = EPOLLEvents(rawValue: EPOLLIN.rawValue)
    static let write = EPOLLEvents(rawValue: EPOLLOUT.rawValue)
    static let hup = EPOLLEvents(rawValue: EPOLLHUP.rawValue)
    static let rdhup = EPOLLEvents(rawValue: EPOLLRDHUP.rawValue)
    static let err = EPOLLEvents(rawValue: EPOLLERR.rawValue)
    static let pri = EPOLLEvents(rawValue: EPOLLPRI.rawValue)
    static let edgeTriggered = EPOLLEvents(rawValue: EPOLLET.rawValue)
#endif

}

private extension Socket.Events {

    var epollEvents: EPOLLEvents {
        reduce(EPOLLEvents()) { [$0, $1.epollEvent] }
    }

    static func make(from pollevents: EPOLLEvents) -> Socket.Events {
        var events = Socket.Events()
        if pollevents.contains(.read) {
            events.insert(.read)
        }
        if pollevents.contains(.write) {
            events.insert(.write)
        }
        return events
    }
}

private extension Socket.Event {
    var epollEvent: EPOLLEvents {
        switch self {
        case .read:
            return .read
        case .write:
            return .write
        }
    }
}

#endif
