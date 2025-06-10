export abstract class StorageAdapter<DATA, ID> {
  abstract read(id: ID): Promise<DATA>;
  abstract write(data: DATA): Promise<ID>;
}
