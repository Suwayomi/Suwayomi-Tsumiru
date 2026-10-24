// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/about_repository.dart';
import '../../../data/graphql/__generated__/about_webui.graphql.dart';
import '../../../domain/about/about_dto.dart';

part 'about_controller.g.dart';

@riverpod
Future<AboutDto?> about(Ref ref) =>
    ref.watch(aboutRepositoryProvider).getAbout();

@riverpod
Future<Query$GetAboutWebUI$aboutWebUI?> aboutWebUI(Ref ref) =>
    ref.watch(aboutRepositoryProvider).getAboutWebUI();

@riverpod
PackageInfo packageInfo(Ref ref) => throw UnimplementedError();
