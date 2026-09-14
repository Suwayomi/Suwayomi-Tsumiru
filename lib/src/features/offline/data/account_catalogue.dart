class AccountCatalogue {
  const AccountCatalogue({
    required this.id,
    required this.owner,
    required this.path,
    required this.bytes,
    this.username,
    this.address,
  });

  final String id;
  final String owner;
  final String path;
  final int bytes;
  final String? username;
  final String? address;
}

abstract class AccountCatalogueRepository {
  Future<List<AccountCatalogue>> list({String? activePath});
  Future<void> remove(
    AccountCatalogue catalogue, {
    required bool Function() canRemove,
  });
}
