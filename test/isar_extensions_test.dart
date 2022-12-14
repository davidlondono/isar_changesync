import 'package:isar_crdt/store/store.dart';
import 'package:isar_crdt/utils/hlc.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:isar/isar.dart';

import 'package:isar_crdt/isar_crdt.dart';

import 'isar_extensions_test.mocks.dart';
import 'models/models.dart';
import 'utils/fake_isar.dart';

class MockObject extends CrdtBaseObject {
  int id = Isar.autoIncrement;
  MockObject();

  @override
  Map<String, dynamic> toJson() {
    return {
      "sid": sid,
      "fake": "fake",
    };
  }
}

class FakeQuery<T> extends Mock implements Query<T> {
  @override
  Future<List<Map<String, dynamic>>> exportJson() {
    return Future.value(<Map<String, dynamic>>[]);
  }
}

extension MockQueryBuilderE on MockQueryBuilder {
  QueryBuilder<MockObject, MockObject, QAfterFilterCondition> anyOf<E, RS>(
    Iterable<E> items,
    FilterRepeatModifier<MockObject, MockObject, E> modifier,
  ) {
    return this as QueryBuilder<MockObject, MockObject, QAfterFilterCondition>;
  }
}

int Function(MockObject) returnGetId() => (MockObject obj) => obj.id;
QueryBuilderInternal<MockObject> returnQuery() => MockQueryBuilderInternal();

@GenerateMocks([
  CrdtStore
], customMocks: [
  MockSpec<IsarCrdt>(
      as: #MockIsarCrdt, onMissingStub: OnMissingStub.returnDefault),
  MockSpec<IsarCollection<MockObject>>(
      as: #MockIsarCollection, onMissingStub: OnMissingStub.returnDefault),
  MockSpec<QueryBuilder<MockObject, MockObject, QFilterCondition>>(
      as: #MockQueryBuilder),
  MockSpec<QueryBuilderInternal<MockObject>>(as: #MockQueryBuilderInternal),
  MockSpec<CollectionSchema<MockObject>>(
      as: #MockCollectionSchema, onMissingStub: OnMissingStub.returnDefault)
])
void main() {
  final mockIsar = MockIsar();
  late Isar isar;
  // Create a mock IsarCrdt processor
  final store = MockCrdtStore();
  final collection = MockIsarCollection();
  final schema = MockCollectionSchema();
  final query = MockQueryBuilder();

  final mockProcessor = IsarCrdt(
    store: store,
  );
  setUp(() async {
    // Call the registerChanges() method
    await Isar.initializeIsarCore(download: true);

    isar = await Isar.open(
      [CarModelSchema],
    );

    mockIsar.setCrdt(mockProcessor);
    isar.setCrdt(mockProcessor);
    when(store.canonicalTime()).thenAnswer((_) async => Hlc.now('nodeId'));
    when(collection.name).thenReturn("MockIsarCollection");
    when(collection.schema).thenReturn(schema);
    when(collection.isar).thenReturn(mockIsar);
    when(collection.filter()).thenReturn(query);
  });

  // tearDownAll(() => isar.writeTxn(() => isar.clear()));

  tearDown(() => isar.close(deleteFromDisk: true));
  test('IsarC.registerChanges() adds processor to list', () {
    // Check that the mock processor has been added to the list
    expect(isar.crdt!.store, store);
  });

  test('IsarCollectionChanges.getSid() return .sid of object', () {
    // Create a collection mock
    final mocked = MockObject()..sid = "fake sid";

    // Call the getSid() method
    expect(collection.getSid(mocked), "fake sid");
  });

  test('IsarCollectionChanges.toJson() return map of object', () {
    // Create a collection mock
    final mocked = MockObject()..sid = "fake sid";

    final json = collection.toJson(mocked);
    // Call the getSid() method
    expect(json, isA<Map<String, dynamic>>());
    expect(json["sid"], "fake sid");
    expect(json["fake"], "fake");
  });
  test(
      "IsarCollectionChanges.deleteAllChanges must register deletion of objects",
      () async {
    // arrange

    when(collection.getAll([1, 2, 3])).thenAnswer((_) async => [
          MockObject()..sid = "sid_1",
          MockObject()..sid = "sid_2",
          MockObject()..sid = "sid_3",
        ]);
    when(collection.deleteAll([1, 2, 3])).thenAnswer((_) async => 3);

    // call
    await collection.deleteAllChanges([1, 2, 3]);

    // test
    final verifySaveChanges = verify(store.storeChanges(captureAny));
    expect(verifySaveChanges.callCount, 1);
    expect(verifySaveChanges.captured.single, isA<List<NewOperationChange>>());
    expect(
        verifySaveChanges.captured.single,
        equals([
          NewOperationChange.delete(collection: collection.name, sid: "sid_1"),
          NewOperationChange.delete(collection: collection.name, sid: "sid_2"),
          NewOperationChange.delete(collection: collection.name, sid: "sid_3")
        ]));
  });

  group("IsarCollectionChanges.putAllChanges", () {
    test("must register new items", () async {
      // arrange
      final mocked = [
        CarModel.fabric("1")..sid = "sid_1",
        CarModel.fabric("2")..sid = "sid_2",
        CarModel.fabric("3")..sid = "sid_3",
      ];
      final carCollection = isar.collection<CarModel>();

      // call
      await isar.writeTxn(() async {
        return carCollection.putAllChanges(mocked);
      });

      final verifySaveChanges = verify(store.storeChanges(captureAny));
      expect(verifySaveChanges.callCount, 1);
      final capturedOperations = verifySaveChanges.captured.single;
      expect(capturedOperations, isA<List<NewOperationChange>>());

      final operations = [
        NewOperationChange.insert(
            collection: CarModelSchema.name,
            sid: "sid_1",
            value: {"make": "make 1", "year": "year 1"}),
        NewOperationChange.insert(
            collection: CarModelSchema.name,
            sid: "sid_2",
            value: {"make": "make 2", "year": "year 2"}),
        NewOperationChange.insert(
            collection: CarModelSchema.name,
            sid: "sid_3",
            value: {"make": "make 3", "year": "year 3"})
      ];
      expect(capturedOperations, equals(operations));
    });
    test("must register edited items", () async {
      // arrange
      final carOne = CarModel.fabric("1")..sid = "sid_1";
      final mocked = [
        carOne,
        CarModel.fabric("2")..sid = "sid_edit_2",
        CarModel.fabric("3")..sid = "sid_edit_3",
      ];
      final carCollection = isar.collection<CarModel>();

      // call
      await isar.writeTxn(() async {
        await carCollection.putAll(mocked);
        final car = await carCollection.getBySid("sid_1");
        car!.year = "year 1 edited";
        car.make = "make 1 edited";
        return carCollection.putChanges(car);
      });

      final verifySaveChanges = verify(store.storeChanges(captureAny));
      expect(verifySaveChanges.callCount, 1);
      final capturedOperations = verifySaveChanges.captured.single;
      expect(capturedOperations, isA<List<NewOperationChange>>());

      final operations = [
        NewOperationChange.edit(
            collection: CarModelSchema.name,
            sid: "sid_1",
            field: "make",
            value: "make 1 edited"),
        NewOperationChange.edit(
            collection: CarModelSchema.name,
            sid: "sid_1",
            field: "year",
            value: "year 1 edited"),
      ];
      expect(capturedOperations, equals(operations));
    });
  });
}
