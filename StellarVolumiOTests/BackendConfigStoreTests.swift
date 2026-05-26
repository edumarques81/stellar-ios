import XCTest
@testable import StellarVolumiO

/// Tests for `BackendConfigStore`. Each test uses a private `UserDefaults`
/// suite so the assertions never interfere with the app's real preferences
/// (or with each other when run in parallel).
@MainActor
final class BackendConfigStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "BackendConfigStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Default fallback (the original behaviour)

    func testFallsBackToHardcodedDefaultWhenNoConfigPresent() {
        let store = BackendConfigStore(defaults: defaults)
        XCTAssertEqual(store.host, "192.168.86.221",
                       "out-of-the-box host must match the previous hardcoded constant")
        XCTAssertEqual(store.port, 3000)
        XCTAssertEqual(store.scheme, "http")
        XCTAssertEqual(store.currentURLString, "http://192.168.86.221:3000")
        XCTAssertFalse(store.hasCustomConfig)
    }

    // MARK: - Custom takes priority

    func testCustomConfigOverridesDiscoveredAndDefault() throws {
        let store = BackendConfigStore(defaults: defaults)
        store.recordDiscovered(host: "10.0.0.5", port: 4000)
        try store.setCustom(host: "stellar.local", port: 3100, scheme: "https")

        XCTAssertEqual(store.host, "stellar.local",
                       "custom host beats both discovered + default")
        XCTAssertEqual(store.port, 3100)
        XCTAssertEqual(store.scheme, "https")
        XCTAssertTrue(store.hasCustomConfig)
    }

    func testCustomPersistsAcrossInstances() throws {
        let first = BackendConfigStore(defaults: defaults)
        try first.setCustom(host: "stellar.local", port: 4500, scheme: "http")

        let second = BackendConfigStore(defaults: defaults)
        XCTAssertEqual(second.host, "stellar.local")
        XCTAssertEqual(second.port, 4500)
        XCTAssertEqual(second.scheme, "http")
    }

    // MARK: - Discovered as middle tier

    func testDiscoveredUsedWhenNoCustomPresent() {
        let store = BackendConfigStore(defaults: defaults)
        store.recordDiscovered(host: "10.0.0.5", port: 4000)

        XCTAssertEqual(store.host, "10.0.0.5",
                       "with no custom config, discovered host wins over default")
        XCTAssertEqual(store.port, 4000)
        // Scheme has no Bonjour analogue — falls through to default.
        XCTAssertEqual(store.scheme, "http")
    }

    func testClearCustomFallsBackToDiscovered() throws {
        let store = BackendConfigStore(defaults: defaults)
        store.recordDiscovered(host: "10.0.0.5", port: 4000)
        try store.setCustom(host: "stellar.local", port: 3100, scheme: "https")
        XCTAssertEqual(store.host, "stellar.local")

        store.clearCustom()
        XCTAssertEqual(store.host, "10.0.0.5",
                       "after clearCustom, fallback chain drops to discovered")
        XCTAssertEqual(store.port, 4000)
        XCTAssertEqual(store.scheme, "http",
                       "with no custom scheme present, scheme falls back to default")
        XCTAssertFalse(store.hasCustomConfig)
    }

    func testClearCustomFallsAllTheWayToDefaultWhenNoDiscovery() throws {
        let store = BackendConfigStore(defaults: defaults)
        try store.setCustom(host: "stellar.local", port: 3100, scheme: "https")
        store.clearCustom()

        XCTAssertEqual(store.host, BackendConfigStore.defaultHost)
        XCTAssertEqual(store.port, BackendConfigStore.defaultPort)
        XCTAssertEqual(store.scheme, BackendConfigStore.defaultScheme)
    }

    // MARK: - Validation

    func testEmptyHostRejected() {
        let store = BackendConfigStore(defaults: defaults)
        XCTAssertThrowsError(try store.setCustom(host: "", port: nil, scheme: nil)) { error in
            XCTAssertEqual(error as? BackendConfigStore.ValidationError, .emptyHost)
        }
        XCTAssertThrowsError(try store.setCustom(host: "   ", port: nil, scheme: nil))
        XCTAssertFalse(store.hasCustomConfig, "validation failure must not write to storage")
    }

    func testInvalidPortRejected() {
        let store = BackendConfigStore(defaults: defaults)
        for bad in [0, -1, 65536, 99999] {
            XCTAssertThrowsError(try store.setCustom(host: nil, port: bad, scheme: nil)) { error in
                XCTAssertEqual(error as? BackendConfigStore.ValidationError, .invalidPort,
                               "port \(bad) must be rejected")
            }
        }
        XCTAssertFalse(store.hasCustomConfig)
    }

    func testValidPortsAccepted() throws {
        let store = BackendConfigStore(defaults: defaults)
        try store.setCustom(host: "x", port: 1, scheme: nil)
        XCTAssertEqual(store.port, 1)
        try store.setCustom(host: "x", port: 65535, scheme: nil)
        XCTAssertEqual(store.port, 65535)
    }

    func testInvalidSchemeRejected() {
        let store = BackendConfigStore(defaults: defaults)
        for bad in ["ftp", "ws", "", "tcp"] {
            XCTAssertThrowsError(try store.setCustom(host: nil, port: nil, scheme: bad)) { error in
                XCTAssertEqual(error as? BackendConfigStore.ValidationError, .invalidScheme,
                               "scheme \(bad) must be rejected")
            }
        }
    }

    func testSchemeAcceptedCaseInsensitively() throws {
        let store = BackendConfigStore(defaults: defaults)
        try store.setCustom(host: "x", port: nil, scheme: "HTTPS")
        XCTAssertEqual(store.scheme, "https")
        try store.setCustom(host: "x", port: nil, scheme: " http ")
        XCTAssertEqual(store.scheme, "http")
    }

    // MARK: - Discovered persistence

    func testRecordDiscoveredPersists() {
        let first = BackendConfigStore(defaults: defaults)
        first.recordDiscovered(host: "192.168.5.10", port: 3001)

        let second = BackendConfigStore(defaults: defaults)
        XCTAssertEqual(second.host, "192.168.5.10")
        XCTAssertEqual(second.port, 3001)
    }

    func testRecordDiscoveredRejectsGarbage() {
        let store = BackendConfigStore(defaults: defaults)
        store.recordDiscovered(host: "", port: 3000)
        store.recordDiscovered(host: "   ", port: 3000)
        store.recordDiscovered(host: "ok", port: 0)
        store.recordDiscovered(host: "ok", port: 70000)

        XCTAssertEqual(store.host, BackendConfigStore.defaultHost,
                       "garbage discovery values must not corrupt the fallback chain")
    }

    // MARK: - host:port disambiguation (regression: app panic 2026-05-27)
    //
    // A user typing "Eduardos-Laptop.local:3000" into Settings' Manual entry
    // host field used to be stored verbatim. SocketService later built
    // "http://Eduardos-Laptop.local:3000:3000" — URL(string:) returns nil,
    // and the force-unwrap crashed the app on every launch.
    // setCustom() must split host:port at the boundary and store them
    // separately, AND the host getter must sanitize any pre-existing dirty
    // storage on read so already-crashed users can recover without a
    // reinstall.

    func testSetCustomSplitsHostAndPortWhenHostContainsColon() throws {
        let store = BackendConfigStore(defaults: defaults)
        try store.setCustom(host: "Eduardos-Laptop.local:3000", port: nil, scheme: nil)
        XCTAssertEqual(store.host, "Eduardos-Laptop.local",
                       "setCustom must strip :port from the host field")
        XCTAssertEqual(store.port, 3000,
                       "setCustom must promote the trailing :port into the port slot")
    }

    func testSetCustomExplicitPortBeatsEmbeddedPort() throws {
        // When the caller passes BOTH an embedded port in the host AND an
        // explicit port argument, the explicit one wins — the form's port
        // field is the authoritative input.
        let store = BackendConfigStore(defaults: defaults)
        try store.setCustom(host: "foo.local:9999", port: 4242, scheme: nil)
        XCTAssertEqual(store.host, "foo.local")
        XCTAssertEqual(store.port, 4242)
    }

    func testSetCustomStripsSchemePrefixFromHost() throws {
        // Users sometimes paste a full URL into the host field. Strip it.
        let store = BackendConfigStore(defaults: defaults)
        try store.setCustom(host: "http://foo.local:3000", port: nil, scheme: nil)
        XCTAssertEqual(store.host, "foo.local")
        XCTAssertEqual(store.port, 3000)
    }

    func testSetCustomRejectsInvalidEmbeddedPort() {
        let store = BackendConfigStore(defaults: defaults)
        XCTAssertThrowsError(try store.setCustom(host: "foo:bad", port: nil, scheme: nil)) { err in
            XCTAssertEqual(err as? BackendConfigStore.ValidationError, .invalidPort,
                           "non-numeric embedded port must surface as invalidPort, not be silently dropped")
        }
        XCTAssertThrowsError(try store.setCustom(host: "foo:70000", port: nil, scheme: nil)) { err in
            XCTAssertEqual(err as? BackendConfigStore.ValidationError, .invalidPort)
        }
    }

    func testHostGetterSanitizesPreExistingDirtyStorage() {
        // Simulate an already-crashed user: the bad form-input was persisted
        // verbatim by a previous (pre-fix) build. The new code must clean it
        // on read so the app can launch without a reinstall.
        defaults.set("Eduardos-Laptop.local:3000", forKey: BackendConfigStore.Key.customHost)
        let store = BackendConfigStore(defaults: defaults)
        XCTAssertEqual(store.host, "Eduardos-Laptop.local",
                       "stale dirty storage must not crash the URL builder on next launch")
    }

    func testCurrentURLStringNeverContainsDoublePort() {
        // Defense-in-depth: even if storage somehow has dirt the getter
        // missed, currentURLString (and by extension the SocketService URL)
        // must produce a parseable scheme://host:port form.
        defaults.set("foo:3000", forKey: BackendConfigStore.Key.customHost)
        let store = BackendConfigStore(defaults: defaults)
        let url = URL(string: store.currentURLString)
        XCTAssertNotNil(url, "currentURLString must always be parseable; got \(store.currentURLString)")
    }
}
