import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/features/account/data/account_administration.dart';
import 'package:tsumiru/src/features/account/data/account_permission.dart';
import 'package:tsumiru/src/features/account/data/account_repository.dart';
import 'package:tsumiru/src/features/account/data/graphql/__generated__/account.graphql.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

class AdminLink extends Link {
  final requests = <Request>[];
  Response Function(Request)? respond;
  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    requests.add(request);
    yield respond?.call(request) ??
        Response(
          response: {},
          data: {
            '__typename': 'Query',
            'users': {
              '__typename': 'UserNodeList',
              'nodes': <dynamic>[],
              'totalCount': 0,
              'pageInfo': {
                '__typename': 'PageInfo',
                'hasNextPage': false,
                'hasPreviousPage': false,
                'startCursor': null,
                'endCursor': null,
              },
            },
          },
        );
  }
}

AccountAccess adminAccess({bool admin = false, bool granted = true}) =>
    AccountAccess(
      capability: AccountCapability.supported,
      user: Fragment$AccountDto(
        id: 3,
        username: 'manager',
        roles: [admin ? Enum$UserRole.ADMIN : Enum$UserRole.USER],
        permissions: [if (granted) Enum$UserPermission.MANAGE_USERS],
      ),
    );

void main() {
  late AdminLink link;
  late AccountAccess access;
  late AccountRepository repository;
  setUp(() {
    link = AdminLink();
    access = adminAccess();
    repository = AccountRepository(
      GraphQLClient(link: link, cache: GraphQLCache()),
      access: () => access,
    );
  });

  test(
    'user paging passes the cursor and case-insensitive username filter',
    () async {
      await repository.users(first: 25, after: 42, search: ' Reader ');
      expect(link.requests.single.variables, {
        'first': 25,
        'after': '42',
        'filter': {
          'username': {'includesInsensitive': 'Reader'},
        },
      });
      await repository.users(first: 25, search: ' ');
      expect(link.requests.last.variables['filter'], isNull);
      expect(link.requests.last.variables['after'], isNull);
    },
  );

  for (final capability in [
    AccountCapability.unknown,
    AccountCapability.unsupported,
  ]) {
    test('$capability cannot issue administration requests', () async {
      access = AccountAccess(capability: capability);
      final calls = <Future<dynamic> Function()>[
        () => repository.users(first: 25),
        () => repository.codes(),
        () => repository.register(
          Input$RegisterInput(username: 'a', password: 'b'),
        ),
        () => repository.updateAccount(
          Input$UpdateUserInput(userId: 2, permissions: []),
        ),
        () => repository.createRegistrationCode(
          Input$CreateRegistrationCodeInput(),
        ),
        () => repository.createRecoveryCode(
          Input$CreateRecoveryCodeInput(userId: 2),
        ),
        () => repository.revokeCode(Input$RevokeUserCodeInput(id: 4)),
      ];
      for (final call in calls) {
        await expectLater(call(), throwsA(isA<AccountPermissionDenied>()));
      }
      expect(link.requests, isEmpty);
    });
  }

  test(
    'nonadministrators omit role and replace the complete permission list',
    () {
      final input = accountPermissionUpdate(
        userId: 5,
        permissions: [Enum$UserPermission.DOWNLOAD_CHAPTERS],
        canEditRoles: false,
        role: Enum$UserRole.ADMIN,
      );
      expect(input.toJson(), {
        'userId': 5,
        'permissions': ['DOWNLOAD_CHAPTERS'],
      });
      expect(
        accountPermissionUpdate(
          userId: 5,
          permissions: [],
          canEditRoles: true,
          role: Enum$UserRole.USER,
        ).toJson(),
        {'userId': 5, 'permissions': [], 'role': 'USER'},
      );
    },
  );

  test('issued codes remain outside GraphQL cache and retain expiry', () async {
    link.respond = (request) => Response(
      response: {},
      data: {
        '__typename': 'Mutation',
        'createRegistrationCode': {
          '__typename': 'CreateRegistrationCodePayload',
          'code': 'one-time-registration',
          'expiresAt': '1900000000',
        },
        'createRecoveryCode': {
          '__typename': 'CreateRecoveryCodePayload',
          'code': 'one-time-recovery',
          'expiresAt': '1900000001',
        },
      },
    );
    final registration = await repository.createRegistrationCode(
      Input$CreateRegistrationCodeInput(),
    );
    final recovery = await repository.createRecoveryCode(
      Input$CreateRecoveryCodeInput(userId: 5),
    );
    expect(registration?.code, 'one-time-registration');
    expect(recovery?.expiresAt, '1900000001');
    expect(link.requests.last.variables, {
      'input': {'userId': 5},
    });
    expect(
      repository.client.cache.store.toMap().toString(),
      isNot(contains('one-time-')),
    );
  });
}
