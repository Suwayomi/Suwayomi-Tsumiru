import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/utils/webui_meta/saved_search_filters.dart';

void main() {
  test('WebUI saved search preserves every primitive state and group path', () {
    final search =
        jsonDecode('''{
      "query":"adventure",
      "filters":[
        {"type":"textState","positions":[0],"state":"pirates"},
        {"type":"checkBoxState","positions":[1],"state":false},
        {"type":"selectState","positions":[2],"state":0},
        {"type":"triState","positions":[3,0],"state":"IGNORE"},
        {"type":"triState","positions":[3,1],"state":"INCLUDE"},
        {"type":"triState","positions":[3,2],"state":"EXCLUDE"},
        {"type":"sortState","positions":[4],"state":{"index":2,"ascending":false}},
        {"type":"sortState","positions":[5,1],"state":{"index":0,"ascending":true}},
        {"type":"textState","positions":[6,1,2],"state":""}
      ]
    }''')
            as Map<String, dynamic>;
    final changes = filtersFromWebUi(search['filters'] as List);
    expect(changes[4].groupChange!.triState!.name, 'INCLUDE');
    expect(changes[7].groupChange!.sortState!.ascending, true);
    expect(changes[8].groupChange!.groupChange!.textState, '');
    expect(filtersToWebUi(changes), search['filters']);
  });
}
