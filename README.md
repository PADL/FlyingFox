[![Build](https://github.com/swhitty/FlyingFox/actions/workflows/build.yml/badge.svg)](https://github.com/swhitty/FlyingFox/actions/workflows/build.yml)
[![Codecov](https://codecov.io/gh/swhitty/FlyingFox/graphs/badge.svg)](https://codecov.io/gh/swhitty/FlyingFox)
[![Platforms](https://img.shields.io/badge/platforms-iOS%20|%20Mac%20|%20tvOS%20|%20Linux%20|%20Windows-lightgray.svg)](https://github.com/swhitty/FlyingFox/blob/main/Package.swift)
[![Swift 5.6](https://img.shields.io/badge/swift-5.5%20|%205.7-red.svg?style=flat)](https://developer.apple.com/swift)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](https://opensource.org/licenses/MIT)
[![Twitter](https://img.shields.io/badge/twitter-@simonwhitty-blue.svg)](http://twitter.com/simonwhitty)

- [Usage](#usage)
- [Handlers](#handlers)
- [Routes](#routes)
- [WebSockets](#websockets)
- [FlyingSocks](#flyingsocks)
    - [Socket](#socket)
    - [AsyncSocket](#asyncsocket)
        - [AsyncSocketPool](#asyncsocketpool)
        - [PollingSocketPool](#pollingsocketpool)
        - [EventQueueSocketPool](#eventqueuesocketpool)
    - [SocketAddress](#socketaddress)
- [Command Line App](#command-line-app)
- [Credits](#credits)

# Introduction

**FlyingFox** is a lightweight HTTP server built using [Swift Concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html). The server uses non blocking BSD sockets, handling each connection in a concurrent child [Task](https://developer.apple.com/documentation/swift/task). When a socket is blocked with no data, tasks are suspended using the shared [`AsyncSocketPool`](#pollingsocketpool).

# Installation

FlyingFox can be installed by using Swift Package Manager.

**Note:** FlyingFox requires Swift 5.5 on Xcode 13.2+. It runs on iOS 13+, tvOS 13+, macOS 10.15+ and Linux. Windows 10 support is experimental.

To install using Swift Package Manager, add this to the `dependencies:` section in your Package.swift file:

```swift
.package(url: "https://github.com/swhitty/FlyingFox.git", .upToNextMajor(from: "0.8.0"))
```

# Usage

Start the server by providing a port number:

```swift
import FlyingFox

let server = HTTPServer(port: 80)
try await server.start()
```

The server runs within the the current task. To stop the server, cancel the task terminating all connections immediatley:

```swift
let task = Task { try await server.start() }
task.cancel()
```

Gracefully shutdown the server after all existing requests complete, otherwise forcefully closing after a timeout:

```swift
await server.stop(timeout: 3)
```

Wait until the server is listening and ready for connections:

```swift
try await server.waitUntilListening()
```

Retrieve the current listening address:

```swift
await server.listeningAddress
```

> Note: iOS will hangup the listening socket when an app is suspended in the background. Once the app returns to the foreground, `HTTPServer.start()` detects this, throwing `SocketError.disconnected`. The server must then be started once more.

## Handlers

Handlers can be added to the server by implementing `HTTPHandler`:

```swift
protocol HTTPHandler {
  func handleRequest(_ request: HTTPRequest) async throws -> HTTPResponse
}
```

Routes can be added to the server delegating requests to a handler:

```swift
await server.appendRoute("/hello", to: handler)
```

They can also be added to closures:

```swift
await server.appendRoute("/hello") { request in
  try await Task.sleep(nanoseconds: 1_000_000_000)
  return HTTPResponse(statusCode: .ok)
}
```

Incoming requests are routed to the handler of the first matching route.

Handlers can throw `HTTPUnhandledError` if after inspecting the request, they cannot handle it.  The next matching route is then used.

Requests that do not match any handled route receive `HTTP 404`.

### FileHTTPHandler

Requests can be routed to static files with `FileHTTPHandler`:

```swift
await server.appendRoute("GET /mock", to: .file(named: "mock.json"))
```

`FileHTTPHandler` will return `HTTP 404` if the file does not exist.

### DirectoryHTTPHandler

Requests can be routed to static files within a directory with `DirectoryHTTPHandler`:

```swift
await server.appendRoute("GET /mock/*", to: .directory(subPath: "Stubs", serverPath: "mock"))
// GET /mock/fish/index.html  ---->  Stubs/fish/index.html
```

`DirectoryHTTPHandler` will return `HTTP 404` if a file does not exist.

### ProxyHTTPHandler

Requests can be proxied via a base URL:

```swift
await server.appendRoute("GET *", to: .proxy(via: "https://pie.dev"))
// GET /get?fish=chips  ---->  GET https://pie.dev/get?fish=chips
```

### RedirectHTTPHandler

Requests can be redirected to a URL:

```swift
await server.appendRoute("GET /fish/*", to: .redirect(to: "https://pie.dev/get"))
// GET /fish/chips  --->  HTTP 301
//                        Location: https://pie.dev/get
```

### WebSocketHTTPHandler

Requests can be routed to a websocket by providing a `WSMessageHandler` where a pair of `AsyncStream<WSMessage>` are exchanged:
```swift
await server.appendRoute("GET /socket", to: .webSocket(EchoWSMessageHandler()))

protocol WSMessageHandler {
  func makeMessages(for client: AsyncStream<WSMessage>) async throws -> AsyncStream<WSMessage>
}

enum WSMessage {
  case text(String)
  case data(Data)
}
```

Raw WebSocket frames can also be [provided](#websockets).

### RoutedHTTPHandler

Multiple handlers can be grouped with requests and matched against `HTTPRoute` using `RoutedHTTPHandler`.

```swift
var routes = RoutedHTTPHandler()
routes.appendRoute("GET /fish/chips", to: .file(named: "chips.json"))
routes.appendRoute("GET /fish/mushy_peas", to: .file(named: "mushy_peas.json"))
await server.appendRoute(for: "GET /fish/*", to: routes)
```

`HTTPUnhandledError` is thrown when it's unable to handle the request with any of its registered handlers.

## Routes

`HTTPRoute` is designed to be [pattern matched](https://docs.swift.org/swift-book/ReferenceManual/Patterns.html#ID426) against `HTTPRequest`, allowing requests to be identified by some or all of its properties. 

```swift
let route = HTTPRoute("/hello/world")

route ~= HTTPRequest(method: .GET, path: "/hello/world") // true
route ~= HTTPRequest(method: .POST, path: "/hello/world") // true
route ~= HTTPRequest(method: .GET, path: "/hello/") // false
```

Routes are `ExpressibleByStringLiteral` allowing literals to be automatically converted to `HTTPRoute`:

```swift
let route: HTTPRoute = "/hello/world"
```

Routes can include a specific method to match against:

```swift
let route = HTTPRoute("GET /hello/world")

route ~= HTTPRequest(method: .GET, path: "/hello/world") // true
route ~= HTTPRequest(method: .POST, path: "/hello/world") // false
```

They can also use wildcards within the path:

```swift
let route = HTTPRoute("GET /hello/*/world")

route ~= HTTPRequest(method: .GET, path: "/hello/fish/world") // true
route ~= HTTPRequest(method: .GET, path: "/hello/dog/world") // true
route ~= HTTPRequest(method: .GET, path: "/hello/fish/sea") // false
```

Trailing wildcards match all trailing path components:

```swift
let route = HTTPRoute("/hello/*")

route ~= HTTPRequest(method: .GET, path: "/hello/fish/world") // true
route ~= HTTPRequest(method: .GET, path: "/hello/dog/world") // true
route ~= HTTPRequest(method: .POST, path: "/hello/fish/deep/blue/sea") // true
```

Specific query items can be matched:

```swift
let route = HTTPRoute("/hello?time=morning")

route ~= HTTPRequest(method: .GET, path: "/hello?time=morning") // true
route ~= HTTPRequest(method: .GET, path: "/hello?count=one&time=morning") // true
route ~= HTTPRequest(method: .GET, path: "/hello") // false
route ~= HTTPRequest(method: .GET, path: "/hello?time=afternoon") // false
```

Query item values can include wildcards:

```swift
let route = HTTPRoute("/hello?time=*")

route ~= HTTPRequest(method: .GET, path: "/hello?time=morning") // true
route ~= HTTPRequest(method: .GET, path: "/hello?time=afternoon") // true
route ~= HTTPRequest(method: .GET, path: "/hello") // false
```

HTTP headers can be matched:

```swift
let route = HTTPRoute("*", headers: [.contentType: "application/json"])

route ~= HTTPRequest(headers: [.contentType: "application/json"]) // true
route ~= HTTPRequest(headers: [.contentType: "application/xml"]) // false
```

Header values can be wildcards:

```swift
let route = HTTPRoute("*", headers: [.authorization: "*"])

route ~= HTTPRequest(headers: [.authorization: "abc"]) // true
route ~= HTTPRequest(headers: [.authorization: "xyz"]) // true
route ~= HTTPRequest(headers: [:]) // false
```

Body patterns can be created to match the request body data:

```swift
public protocol HTTPBodyPattern: Sendable {
  func evaluate(_ body: Data) -> Bool
}
```

Darwin platforms can pattern match a JSON body with an [`NSPredicate`](https://developer.apple.com/documentation/foundation/nspredicate):

```swift
let route = HTTPRoute("POST *", body: .json(where: "food == 'fish'"))
```
```json
{"side": "chips", "food": "fish"}
```

## WebSockets
`HTTPResponse` can switch the connection to the [WebSocket](https://datatracker.ietf.org/doc/html/rfc6455) protocol by provding a `WSHandler` within the response payload.

```swift
protocol WSHandler {
  func makeFrames(for client: AsyncThrowingStream<WSFrame, Error>) async throws -> AsyncStream<WSFrame>
}
```

`WSHandler` facilitates the exchange of a pair `AsyncStream<WSFrame>` containing the raw websocket frames sent over the connection. While powerful, it is more convenient to exchange streams of messages via [`WebSocketHTTPHandler`](#websockethttphandler).

# FlyingSocks

Internally, FlyingFox uses a thin wrapper around standard BSD sockets. The `FlyingSocks` module provides a cross platform async interface to these sockets;

```swift
import FlyingSocks

let socket = try await AsyncSocket.connected(to: .inet(ip4: "192.168.0.100", port: 80))
try await socket.write(Data([0x01, 0x02, 0x03]))
try socket.close()
```

## Socket

`Socket` wraps a file descriptor and provides a Swift interface to common operations, throwing `SocketError` instead of returning error codes.

```swift
public enum SocketError: LocalizedError {
  case blocked
  case disconnected
  case unsupportedAddress
  case failed(type: String, errno: Int32, message: String)
}
```

When data is unavailable for a socket and the `EWOULDBLOCK` errno is returned, then `SocketError.blocked` is thrown.

## AsyncSocket

`AsyncSocket` simply wraps a `Socket` and provides an async interface.  All async sockets are configured with the flag `O_NONBLOCK`, catching `SocketError.blocked` and then suspending the current task using an `AsyncSocketPool`.  When data becomes available the task is resumed and `AsyncSocket` will retry the operation.

### AsyncSocketPool

```swift
protocol AsyncSocketPool {
  func prepare() async throws
  func run() async throws

  // Suspends current task until a socket is ready to read and/or write
  func suspendSocket(_ socket: Socket, untilReadyFor events: Socket.Events) async throws
}
```

### PollingSocketPool

`PollingSocketPool` is the default pool used within `HTTPServer`. It uses a continuous loop of [`poll(2)`](https://www.freebsd.org/cgi/man.cgi?poll) / [`Task.yield()`](https://developer.apple.com/documentation/swift/task/3814840-yield) to check all sockets awaiting data at a supplied interval. 

The pool can be tuned to adjust both the time spent within [`poll(2)`](https://www.freebsd.org/cgi/man.cgi?poll) and at the end of each iteration with [`Task.yield()`](https://developer.apple.com/documentation/swift/task/3814840-yield) or [`Task.sleep()`](https://developer.apple.com/documentation/swift/task/3862701-sleep)

```swift
let pool = PollingSocketPool(pollInterval: .immediate, loopInterval: .seconds(0.1))
let server = HTTPServer(port: 80, pool: pool)
```

### EventQueueSocketPool

The experimental [`EventQueueSocketPool<Queue>`](https://github.com/swhitty/FlyingFox/blob/main/FlyingSocks/Sources/EventQueueSocketPool.swift) suspends and resume sockets using kernel events without the need to continuosly poll the waiting file descriptors.  The pool uses a queue to add, remove and be notified of events, abstracting [`kqueue(2)`](https://www.freebsd.org/cgi/man.cgi?kqueue) on Darwin platforms and [`epoll(7)`](https://man7.org/linux/man-pages/man7/epoll.7.html) on Linux.

`EventQueueSocketPool<Queue>` and associated types will be made `public` in the future.  In the meantime they can be used like so:

```swift
let server = HTTPServer(port: 80, pool: makeEventQueuePool())
```


## SocketAddress

The `sockaddr` cluster of structures are grouped via conformance to `SocketAddress`
- `sockaddr_in`
- `sockaddr_in6`
- `sockaddr_un`

This allows `HTTPServer` to be started with any of these configured addresses:

```swift
// only listens on localhost 8080
let server = HTTPServer(address: .loopback(port: 8080))
```

It can also be used with [UNIX-domain](https://www.freebsd.org/cgi/man.cgi?query=unix) addresses, allowing private IPC over a socket:

```swift
// only listens on Unix socket "Ants"
let server = HTTPServer(address: .unix(path: "Ants"))
```

You can then [netcat](https://www.freebsd.org/cgi/man.cgi?query=nc) to the socket:
```
% nc -U Ants
```

# Command line app

An example command line app FlyingFoxCLI is available [here](https://github.com/swhitty/FlyingFoxCLI).

# Credits

FlyingFox is primarily the work of [Simon Whitty](https://github.com/swhitty).

([Full list of contributors](https://github.com/swhitty/FlyingFox/graphs/contributors))
