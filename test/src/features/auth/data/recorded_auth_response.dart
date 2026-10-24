import 'package:graphql/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tsumiru/src/utils/network/graphql_errors.dart';

GraphQLClient recordedAuthClient(int status, String body) => GraphQLClient(
  cache: GraphQLCache(),
  link: HttpLink(
    'http://localhost/graphql',
    httpClient: MockClient((_) async => http.Response(body, status)),
    httpResponseDecoder: tsumiruHttpResponseDecoder,
  ),
);
