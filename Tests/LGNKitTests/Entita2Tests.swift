import Foundation
import XCTest
import LGNCore
import NIO
import MessagePack
@testable import Entita2

final class Entita2Tests: XCTestCase {
    static var eventLoop = EmbeddedEventLoop()

    struct DummyStorage: E2Storage {
        func load(
            by key: Bytes,
            within transaction: AnyTransaction?,
            on eventLoop: EventLoop
        ) -> Future<Bytes?> {
            let result: Bytes?

            switch key {
            case TestEntity.sampleEntity.getIDAsKey(): // TestEntity
                result = LGNCore.getBytes("""
                    {
                        "string": "foo",
                        "ints": [322, 1337],
                        "subEntity": {
                            "myValue": "sikes",
                            "customID": 1337
                        },
                        "mapOfBooleans": {
                            "kek": false,
                            "lul": true
                        },
                        "bool": true,
                        "float": 322.1337,
                        "ID": "NHtKl8JnQj+oR4gCRvxpcg=="
                    }
                """)
            case TestEntity.sampleEntity.subEntity.getIDAsKey(): // TestEntity.SubEntity
                result = LGNCore.getBytes("""
                    {
                        "myValue": "sikes",
                        "customID": 1337
                    }
                """)
            case [0]: // invalid
                result = [1, 3, 3, 7, 3, 2, 2]
            default:
                result = nil
            }

            return eventLoop.makeSucceededFuture(result)
        }

        func save(
            bytes: Bytes,
            by key: Bytes,
            within transaction: AnyTransaction?,
            on eventLoop: EventLoop
        ) -> Future<Void> {
            return eventLoop.makeSucceededFuture(Void())
        }

        func delete(
            by key: Bytes,
            within transaction: AnyTransaction?,
            on eventLoop: EventLoop
        ) -> Future<Void> {
            return eventLoop.makeSucceededFuture(Void())
        }
    }

    final class TestEntity: E2Entity, Equatable {
        struct SubEntity: E2Entity, Equatable {
            typealias Identifier = Int
            typealias Storage = DummyStorage

            static var fullEntityName: Bool = false
            static var format: E2.Format = .JSON
            static var storage: Entita2Tests.DummyStorage = DummyStorage()
            static var IDKey: KeyPath<SubEntity, Identifier> = \.customID
            static var sampleEntity: Self {
                Self(customID: 1337, myValue: "sikes")
            }

            var customID: Identifier
            var myValue: String
        }

        enum CodingKeys: String, CodingKey {
            case ID
            case string
            case ints
            case mapOfBooleans
            case float
            case bool
            case subEntity
        }

        typealias Identifier = E2.UUID
        typealias Storage = DummyStorage

        static var format: E2.Format = .JSON
        static var storage: Entita2Tests.DummyStorage = DummyStorage()
        static var IDKey: KeyPath<TestEntity, Identifier> = \.ID
        static var sampleEntity: TestEntity {
            TestEntity(
                ID: E2.UUID("347b4a97-c267-423f-a847-880246fc6972")!,
                string: "foo",
                ints: [322, 1337],
                mapOfBooleans: ["lul": true, "kek": false],
                float: 322.1337,
                bool: true,
                subEntity: SubEntity.sampleEntity
            )
        }

        static func == (lhs: Entita2Tests.TestEntity, rhs: Entita2Tests.TestEntity) -> Bool {
            true
                && lhs.ID == rhs.ID
                && lhs.string == rhs.string
                && lhs.ints == rhs.ints
                && lhs.mapOfBooleans == rhs.mapOfBooleans
                && lhs.float == rhs.float
                && lhs.bool == rhs.bool
                && lhs.subEntity == rhs.subEntity
        }

        var didCallAfterLoad0: Bool = false
        var didCallAfterLoad: Bool = false
        var didCallBeforeSave0: Bool = false
        var didCallBeforeSave: Bool = false
        var didCallAfterSave0: Bool = false
        var didCallAfterSave: Bool = false
        var didCallBeforeInsert0: Bool = false
        var didCallBeforeInsert: Bool = false
        var didCallAfterInsert: Bool = false
        var didCallAfterInsert0: Bool = false
        var didCallBeforeDelete0: Bool = false
        var didCallBeforeDelete: Bool = false
        var didCallAfterDelete0: Bool = false
        var didCallAfterDelete: Bool = false

        public func afterLoad0(on eventLoop: EventLoop) -> Future<Void> {
            self.didCallAfterLoad0 = true
            return eventLoop.makeSucceededFuture()
        }

        public func afterLoad(on eventLoop: EventLoop) -> Future<Void> {
            self.didCallAfterLoad = true
            return eventLoop.makeSucceededFuture()
        }

        func beforeSave0(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
            self.didCallBeforeSave0 = true
            return eventLoop.makeSucceededFuture()
        }

        func beforeSave(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
            self.didCallBeforeSave = true
            return eventLoop.makeSucceededFuture()
        }

        func afterSave0(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
            self.didCallAfterSave0 = true
            return eventLoop.makeSucceededFuture()
        }

        func afterSave(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
            self.didCallAfterSave = true
            return eventLoop.makeSucceededFuture()
        }

        func beforeInsert0(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
            self.didCallBeforeInsert0 = true
            return eventLoop.makeSucceededFuture()
        }

        func beforeInsert(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
            self.didCallBeforeInsert = true
            return eventLoop.makeSucceededFuture()
        }

        func afterInsert(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
            self.didCallAfterInsert = true
            return eventLoop.makeSucceededFuture()
        }

        func afterInsert0(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
            self.didCallAfterInsert0 = true
            return eventLoop.makeSucceededFuture()
        }

        func beforeDelete0(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
            self.didCallBeforeDelete0 = true
            return eventLoop.makeSucceededFuture()
        }

        func beforeDelete(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
            self.didCallBeforeDelete = true
            return eventLoop.makeSucceededFuture()
        }

        func afterDelete0(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
            self.didCallAfterDelete0 = true
            return eventLoop.makeSucceededFuture()
        }

        func afterDelete(within transaction: AnyTransaction?, on eventLoop: EventLoop) -> Future<Void> {
            self.didCallAfterDelete = true
            return eventLoop.makeSucceededFuture()
        }

        var ID: Identifier
        var string: String
        var ints: [Int]
        var mapOfBooleans: [String: Bool]
        var float: Float
        var bool: Bool
        var subEntity: SubEntity

        init(
            ID: Identifier,
            string: String,
            ints: [Int],
            mapOfBooleans: [String: Bool],
            float: Float,
            bool: Bool,
            subEntity: SubEntity
        ) {
            self.ID = ID
            self.string = string
            self.ints = ints
            self.mapOfBooleans = mapOfBooleans
            self.float = float
            self.bool = bool
            self.subEntity = subEntity
        }
    }

    struct InvalidPackEntity: E2Entity {
        typealias Identifier = Int
        typealias Storage = DummyStorage

        static var fullEntityName: Bool = false
        static var format: E2.Format = .JSON
        static var storage: Entita2Tests.DummyStorage = DummyStorage()
        static var IDKey: KeyPath<InvalidPackEntity, Identifier> = \.ID

        var ID: Identifier

        func pack(to format: E2.Format = Self.format) throws -> Bytes {
            throw EncodingError.invalidValue(
                "test",
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "error"
                )
            )
        }
    }

    func testFormats() throws {
        let sampleEntity = TestEntity.sampleEntity

        for format in E2.Format.allCases {
            XCTAssertEqual(
                try TestEntity(from: sampleEntity.pack(to: format), format: format),
                sampleEntity
            )
        }
    }

    func testMockBegin() throws {
        XCTAssert(try TestEntity.begin(on: Self.eventLoop).wait() == nil)
    }

    func testGetID() {
        let sampleEntity = TestEntity.sampleEntity
        let sampleSubEntity = sampleEntity.subEntity
        XCTAssertEqual(sampleEntity.getID(), sampleEntity.ID)
        XCTAssertEqual(sampleSubEntity.getID(), sampleSubEntity.customID)
    }

    func testIDBytes() {
        let sampleEntity = TestEntity.sampleEntity

        let sampleIDBytes = LGNCore.getBytes(sampleEntity.ID)
        let sampleCustomIDBytes = LGNCore.getBytes(sampleEntity.subEntity.customID)
        XCTAssertEqual(sampleEntity.ID._bytes, sampleIDBytes)
        XCTAssertEqual(sampleEntity.subEntity.customID._bytes, sampleCustomIDBytes)

        let prefix = LGNCore.getBytes("TestEntity:")
        XCTAssertEqual(TestEntity.IDBytesAsKey(bytes: [1,2,3]), prefix + [1,2,3])
        XCTAssertEqual(TestEntity.IDAsKey(ID: sampleEntity.ID), prefix + sampleIDBytes)
        XCTAssertEqual(sampleEntity.getIDAsKey(), prefix + sampleIDBytes)
    }

    func testUUIDID() {
        let sampleEntity = TestEntity.sampleEntity
        XCTAssertEqual(sampleEntity.ID.string, sampleEntity.ID.value.uuidString)

        XCTAssertEqual(E2.UUID("invalid"), nil)
        XCTAssertEqual(E2.UUID("53D29EF7-377C-4D14-864B-EB3A85769359"), E2.UUID("53D29EF7-377C-4D14-864B-EB3A85769359"))
    }

    func testEntityName() {
        XCTAssertEqual(TestEntity.entityName, "TestEntity")
        XCTAssertEqual(TestEntity.SubEntity.entityName, "SubEntity")
        TestEntity.SubEntity.fullEntityName = true
        XCTAssertEqual(TestEntity.SubEntity.entityName, "Entita2Tests.TestEntity.SubEntity")
        TestEntity.SubEntity.fullEntityName = false
    }

    func testGetPackedSelf() {
        let future1 = TestEntity.sampleEntity.getPackedSelf(on: Self.eventLoop)
        let future2 = InvalidPackEntity(ID: 1).getPackedSelf(on: Self.eventLoop)

        Self.eventLoop.run()

        XCTAssertNoThrow(try future1.wait())
        XCTAssertThrowsError(try future2.wait())
    }

    func testLoad() throws {
        let sampleEntity = TestEntity.sampleEntity

        let loaded = try TestEntity.loadByRaw(IDBytes: sampleEntity.getIDAsKey(), on: Self.eventLoop).wait()

        XCTAssertEqual(loaded, sampleEntity)

        XCTAssertTrue(loaded!.didCallAfterLoad)
        XCTAssertTrue(loaded!.didCallAfterLoad0)

        XCTAssertEqual(
            try TestEntity.loadBy(IDBytes: sampleEntity.ID._bytes, on: Self.eventLoop).wait(),
            sampleEntity
        )
        XCTAssertEqual(
            try TestEntity.load(by: sampleEntity.ID, on: Self.eventLoop).wait(),
            sampleEntity
        )

        XCTAssertEqual(
            try TestEntity.loadByRaw(IDBytes: [1, 2, 3], on: Self.eventLoop).wait(),
            nil
        )

        XCTAssertThrowsError(
            try TestEntity.loadByRaw(IDBytes: [0], on: Self.eventLoop).wait()
        )
        TestEntity.format = .MsgPack
        XCTAssertThrowsError(
            try TestEntity.loadByRaw(IDBytes: [0], on: Self.eventLoop).wait()
        )
        TestEntity.format = .JSON

        let loadedSubEntity = try TestEntity.SubEntity
            .loadByRaw(IDBytes: sampleEntity.subEntity.getIDAsKey(), on: Self.eventLoop)
            .wait()
        XCTAssertEqual(loadedSubEntity, sampleEntity.subEntity)
    }

    func testSave() throws {
        let sampleEntity = TestEntity.sampleEntity
        let sampleSubEntity = TestEntity.sampleEntity.subEntity

        let future1 = sampleEntity.save(commit: true, on: Self.eventLoop)
        let future2 = sampleSubEntity.save(commit: true, on: Self.eventLoop)
        let future3 = sampleEntity.save(by: sampleEntity.ID, commit: true, on: Self.eventLoop)
        Self.eventLoop.run()
        XCTAssertNoThrow(try future1.wait())
        XCTAssertNoThrow(try future2.wait())
        XCTAssertNoThrow(try future3.wait())

        XCTAssertTrue(sampleEntity.didCallBeforeSave0)
        XCTAssertTrue(sampleEntity.didCallBeforeSave)
        XCTAssertTrue(sampleEntity.didCallAfterSave)
        XCTAssertTrue(sampleEntity.didCallAfterSave0)
    }

    func testInsert() throws {
        let sampleEntity = TestEntity.sampleEntity
        let sampleSubEntity = TestEntity.sampleEntity.subEntity

        let future1 = sampleEntity.insert(commit: true, on: Self.eventLoop)
        let future2 = sampleSubEntity.insert(on: Self.eventLoop)
        Self.eventLoop.run()
        XCTAssertNoThrow(try future1.wait())
        XCTAssertNoThrow(try future2.wait())

        XCTAssertTrue(sampleEntity.didCallBeforeInsert0)
        XCTAssertTrue(sampleEntity.didCallBeforeInsert)
        XCTAssertTrue(sampleEntity.didCallAfterInsert)
        XCTAssertTrue(sampleEntity.didCallAfterInsert0)
    }

    func testDelete() throws {
        let sampleEntity = TestEntity.sampleEntity
        let sampleSubEntity = TestEntity.sampleEntity.subEntity

        let future1 = sampleEntity.delete(commit: true, on: Self.eventLoop)
        let future2 = sampleSubEntity.delete(commit: false, on: Self.eventLoop)
        Self.eventLoop.run()
        XCTAssertNoThrow(try future1.wait())
        XCTAssertNoThrow(try future2.wait())

        XCTAssertTrue(sampleEntity.didCallBeforeDelete0)
        XCTAssertTrue(sampleEntity.didCallBeforeDelete)
        XCTAssertTrue(sampleEntity.didCallAfterDelete)
        XCTAssertTrue(sampleEntity.didCallAfterDelete0)
    }

    static var allTests = [
        ("testFormats", testFormats),
        ("testMockBegin", testMockBegin),
        ("testGetID", testGetID),
        ("testIDBytes", testIDBytes),
        ("testUUIDID", testUUIDID),
        ("testEntityName", testEntityName),
        ("testGetPackedSelf", testGetPackedSelf),
        ("testLoad", testLoad),
        ("testSave", testSave),
        ("testInsert", testInsert),
        ("testDelete", testDelete),
    ]
}
