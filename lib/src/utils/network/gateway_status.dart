// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Origin-down proxy codes; exclude 520/525/526 because they indicate a misbehaving live origin.
bool isGatewayStatus(int status) =>
    status == 502 ||
    status == 503 ||
    status == 504 ||
    (status >= 521 && status <= 524);
