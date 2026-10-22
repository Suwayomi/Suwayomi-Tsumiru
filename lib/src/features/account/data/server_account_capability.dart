import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../utils/network/graphql_errors.dart';
import '../../onboarding/data/server_resolver.dart';
import '../domain/account_access.dart';
import 'graphql/__generated__/account.graphql.dart';

final accountProbeHttpClientProvider = Provider<http.Client Function()>(
  (ref) => http.Client.new,
);

Future<AccountCapability> probeServerAccountCapability(
  String baseUrl, {
  http.Client? client,
  Map<String, String>? headers,
}) async {
  if (baseUrl.isEmpty) return AccountCapability.unknown;
  final owned = client ?? http.Client();
  try {
    final gql = GraphQLClient(
      link: HttpLink(
        graphqlUriFor(baseUrl).toString(),
        httpClient: owned,
        httpResponseDecoder: tsumiruHttpResponseDecoder,
        defaultHeaders: headers ?? const {},
      ),
      cache: GraphQLCache(store: InMemoryStore()),
    );
    final result = await gql
        .query$AccountCapability(
          Options$Query$AccountCapability(fetchPolicy: FetchPolicy.noCache),
        )
        .timeout(const Duration(seconds: 10));
    return classifyAccountResponse(result);
  } on Object {
    return AccountCapability.unknown;
  } finally {
    if (client == null) owned.close();
  }
}
