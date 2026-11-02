String cookieHeaderFromSetCookie(String setCookie) => setCookie
    .split(RegExp(r',(?=\s*[^\s;,=]+=)'))
    .map((cookie) => cookie.split(';').first.trim())
    .where((cookie) => cookie.isNotEmpty)
    .join('; ');
