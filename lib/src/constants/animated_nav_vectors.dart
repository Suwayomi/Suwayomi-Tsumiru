// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:ui';

import 'package:animated_vector/animated_vector.dart';
import 'package:flutter/animation.dart';

// Nav icon animations transcribed from Komikku's animated vector drawables
// (res/drawable/anim_{library,updates,history,browse,more}_enter.xml). Path
// strings are verbatim from the XMLs — do not reformat or "simplify" them:
// morphs require begin/end paths with identical command structure.
// The More paths drop a dangling `c` left by the Lottie export (draws nothing,
// but the SVG path parser rejects it), and its no-op 833 ms filler animator is
// omitted, so its real motion ends at 517 ms.
class AnimatedNavVectors {
  AnimatedNavVectors._();

  // Bodymovin/Shape Shifter exports use custom cubics instead of the framework
  // fastOutSlowIn on the More timeline.
  static const _hopCurve = Cubic(0.5, 0, 0.5, 1);

  static const library = AnimatedVectorData(
    viewportSize: Size(1080, 1080),
    duration: Duration(milliseconds: 300),
    root: RootVectorElement(
      elements: [
        PathElement(
          pathData: PathData.parse(
            'M 634.454 90.84 C 543.069 90.84 451.685 90.84 360.3 90.84 C 310.84 90.84 270.38 131.3 270.38 180.76 C 270.38 360.61 270.38 540.46 270.38 720.31 C 270.38 769.76 310.84 810.23 360.3 810.23 C 540.147 810.23 719.993 810.23 899.84 810.23 C 949.3 810.23 989.77 769.76 989.77 720.31 C 989.77 540.46 989.77 360.61 989.77 180.76 C 989.77 131.3 949.3 90.84 899.84 90.84 C 811.378 90.84 722.916 90.84 634.454 90.84 M 899.84 720.31 C 834.876 720.31 769.913 720.31 704.949 720.31 C 590.066 720.31 475.183 720.31 360.3 720.31 C 360.3 540.46 360.3 360.61 360.3 180.76 C 435.237 180.76 510.173 180.76 585.11 180.76 L 585.11 180.76 C 585.11 315.647 585.11 450.533 585.11 585.42 C 630.073 551.7 675.037 517.98 720 484.26 C 764.96 517.98 809.92 551.7 854.88 585.42 C 854.88 450.533 854.88 315.647 854.88 180.76 C 869.867 180.76 884.853 180.76 899.84 180.76 C 899.84 360.61 899.84 540.46 899.84 720.31',
          ),
          fillColor: Color(0xFF000000),
          properties: PathAnimationProperties(
            pathData: [
              AnimationStep(
                tween: ConstPathDataTween(
                  begin: PathData.parse(
                    'M 634.454 90.84 C 543.069 90.84 451.685 90.84 360.3 90.84 C 310.84 90.84 270.38 131.3 270.38 180.76 C 270.38 360.61 270.38 540.46 270.38 720.31 C 270.38 769.76 310.84 810.23 360.3 810.23 C 540.147 810.23 719.993 810.23 899.84 810.23 C 949.3 810.23 989.77 769.76 989.77 720.31 C 989.77 540.46 989.77 360.61 989.77 180.76 C 989.77 131.3 949.3 90.84 899.84 90.84 C 811.378 90.84 722.916 90.84 634.454 90.84 M 899.84 720.31 C 834.876 720.31 769.913 720.31 704.949 720.31 C 590.066 720.31 475.183 720.31 360.3 720.31 C 360.3 540.46 360.3 360.61 360.3 180.76 C 435.237 180.76 510.173 180.76 585.11 180.76 L 585.11 180.76 C 585.11 315.647 585.11 450.533 585.11 585.42 C 630.073 551.7 675.037 517.98 720 484.26 C 764.96 517.98 809.92 551.7 854.88 585.42 C 854.88 450.533 854.88 315.647 854.88 180.76 C 869.867 180.76 884.853 180.76 899.84 180.76 C 899.84 360.61 899.84 540.46 899.84 720.31',
                  ),
                  end: PathData.parse(
                    'M 900 90 C 720 90 540 90 360 90 C 310.5 90 270 130.5 270 180 C 270 360 270 540 270 720 C 270 769.5 310.5 810 360 810 C 540 810 720 810 900 810 C 949.5 810 990 769.5 990 720 C 990 540 990 360 990 180 C 990 130.5 949.5 90 900 90 C 900 90 900 90 900 90 M 900 540 C 862.5 517.5 825 495 787.5 472.5 C 750 495 712.5 517.5 675 540 C 675 540 675 540 675 540 C 675 471.351 675 402.701 675 334.052 L 675 180 C 675 180 675 180 675 180 C 713.708 180 752.416 180 791.124 180 C 827.416 180 863.708 180 900 180 C 900 233.194 900 286.387 900 339.581 C 900 406.387 900 473.194 900 540 C 900 540 900 540 900 540',
                  ),
                ),
                interval: AnimationInterval(end: Duration(milliseconds: 300)),
                curve: Curves.fastOutSlowIn,
              ),
            ],
          ),
        ),
        PathElement(
          pathData: PathData.parse(
            'M 180.45 270.69 C 180.45 270.69 90.53 270.69 90.53 270.69 C 90.53 270.69 90.53 900.15 90.53 900.15 C 90.53 949.61 131 990.08 180.45 990.08 C 180.45 990.08 809.92 990.08 809.92 990.08 C 809.92 990.08 809.92 900.15 809.92 900.15 C 809.92 900.15 180.45 900.15 180.45 900.15 C 180.45 900.15 180.45 270.69 180.45 270.69',
          ),
          fillColor: Color(0xFF000000),
        ),
      ],
    ),
  );

  static const updates = AnimatedVectorData(
    viewportSize: Size(24, 24),
    duration: Duration(milliseconds: 300),
    root: RootVectorElement(
      elements: [
        PathElement(
          pathData: PathData.parse(
            'M 23 12 L 20.56 9.22 L 20.9 5.54 L 17.29 4.72 L 15.4 1.54 L 12 3 L 8.6 1.54 L 6.71 4.72 L 3.1 5.53 L 3.44 9.21 L 1 12 L 3.44 14.78 L 3.1 18.47 L 6.71 19.29 L 8.6 22.47 L 12 21 L 15.4 22.46 L 17.29 19.28 L 20.9 18.46 L 20.56 14.78 L 23 12 Z M 9.42 19.93 L 7.99 17.52 L 5.25 16.9 L 5.51 14.1 L 3.66 12 L 5.51 9.88 L 5.25 7.1 L 7.99 6.49 L 9.42 4.08 L 12 5.18 L 14.58 4.07 L 16.01 6.48 L 18.75 7.1 L 18.49 9.89 L 20.34 12 L 18.49 14.11 L 18.49 14.11 L 18.75 16.9 L 16.01 17.52 L 14.58 19.93 L 12 18.82 L 9.42 19.93 M 11 15 L 13 15 L 13 15.5 L 13 16 L 13 17 L 11 17 L 11 15 M 11 7 L 13 7 L 13 13 L 11 13 L 11 7',
          ),
          fillColor: Color(0xFF000000),
          properties: PathAnimationProperties(
            pathData: [
              AnimationStep(
                tween: ConstPathDataTween(
                  begin: PathData.parse(
                    'M 23 12 L 20.56 9.22 L 20.9 5.54 L 17.29 4.72 L 15.4 1.54 L 12 3 L 8.6 1.54 L 6.71 4.72 L 3.1 5.53 L 3.44 9.21 L 1 12 L 3.44 14.78 L 3.1 18.47 L 6.71 19.29 L 8.6 22.47 L 12 21 L 15.4 22.46 L 17.29 19.28 L 20.9 18.46 L 20.56 14.78 L 23 12 Z M 9.42 19.93 L 7.99 17.52 L 5.25 16.9 L 5.51 14.1 L 3.66 12 L 5.51 9.88 L 5.25 7.1 L 7.99 6.49 L 9.42 4.08 L 12 5.18 L 14.58 4.07 L 16.01 6.48 L 18.75 7.1 L 18.49 9.89 L 20.34 12 L 18.49 14.11 L 18.49 14.11 L 18.75 16.9 L 16.01 17.52 L 14.58 19.93 L 12 18.82 L 9.42 19.93 M 11 15 L 13 15 L 13 15.5 L 13 16 L 13 17 L 11 17 L 11 15 M 11 7 L 13 7 L 13 13 L 11 13 L 11 7',
                  ),
                  end: PathData.parse(
                    'M 23 12 L 20.56 9.22 L 20.9 5.54 L 17.29 4.72 L 15.4 1.54 L 12 3 L 8.6 1.54 L 6.71 4.72 L 3.1 5.53 L 3.44 9.21 L 1 12 L 3.44 14.78 L 3.1 18.47 L 6.71 19.29 L 8.6 22.47 L 12 21 L 15.4 22.46 L 17.29 19.28 L 20.9 18.46 L 20.56 14.78 L 23 12 Z M 12 13 L 11.5 13 L 11 13 L 11 12 L 11 11 L 11 10 L 11 9 L 11 8 L 11 7 L 12 7 L 13 7 L 13 7.857 L 13 8.714 L 13 9.571 L 13 10.429 L 13 11.286 L 13 12.143 L 13 13 L 13 13 L 13 13 L 12.5 13 L 12 13 M 11 15 L 13 15 L 13 16.058 L 13 17 L 13 17 L 11 17 L 11 15 M 12 10 L 12 10 L 12 10 L 12 10 L 12 10',
                  ),
                ),
                interval: AnimationInterval(end: Duration(milliseconds: 300)),
                curve: Curves.fastOutSlowIn,
              ),
            ],
          ),
        ),
      ],
    ),
  );

  static const history = AnimatedVectorData(
    viewportSize: Size(24, 24),
    duration: Duration(milliseconds: 500),
    root: RootVectorElement(
      elements: [
        PathElement(
          pathData: PathData.parse(
            'M 12 8 L 12 13 L 16.28 15.54 L 17 14.33 L 13.5 12.25 L 13.5 8 L 12 8 Z',
          ),
          fillColor: Color(0xFF000000),
        ),
        GroupElement(
          pivotX: 13,
          pivotY: 12,
          properties: GroupAnimationProperties(
            rotation: [
              AnimationStep(
                tween: ConstTween(begin: 360, end: 0),
                interval: AnimationInterval(end: Duration(milliseconds: 500)),
                curve: Curves.fastOutSlowIn,
              ),
            ],
          ),
          elements: [
            PathElement(
              pathData: PathData.parse(
                'M 13 3 C 8.03 3 4 7.03 4 12 L 1 12 L 4.89 15.89 L 4.96 16.03 L 9 12 L 6 12 C 6 8.13 9.13 5 13 5 C 16.87 5 20 8.13 20 12 C 20 15.87 16.87 19 13 19 C 11.07 19 9.32 18.21 8.06 16.94 L 6.64 18.36 C 8.27 19.99 10.51 21 13 21 C 17.97 21 22 16.97 22 12 C 22 7.03 17.97 3 13 3 Z M 13 3 Z',
              ),
              fillColor: Color(0xFF000000),
            ),
          ],
        ),
      ],
    ),
  );

  static const browse = AnimatedVectorData(
    viewportSize: Size(24, 24),
    duration: Duration(milliseconds: 300),
    root: RootVectorElement(
      elements: [
        GroupElement(
          pivotX: 12,
          pivotY: 12,
          properties: GroupAnimationProperties(
            rotation: [
              AnimationStep(
                tween: ConstTween(begin: 0, end: 180),
                interval: AnimationInterval(end: Duration(milliseconds: 300)),
                curve: Curves.fastOutSlowIn,
              ),
            ],
          ),
          elements: [
            GroupElement(
              pivotX: 12,
              pivotY: 12,
              scaleX: 0,
              scaleY: 0,
              properties: GroupAnimationProperties(
                scaleX: [
                  AnimationStep(
                    tween: ConstTween(begin: 0, end: 1),
                    interval: AnimationInterval(
                      start: Duration(milliseconds: 66),
                      end: Duration(milliseconds: 166),
                    ),
                    curve: Curves.decelerate,
                  ),
                ],
                scaleY: [
                  AnimationStep(
                    tween: ConstTween(begin: 0, end: 1),
                    interval: AnimationInterval(
                      start: Duration(milliseconds: 66),
                      end: Duration(milliseconds: 166),
                    ),
                    curve: Curves.decelerate,
                  ),
                ],
              ),
              elements: [
                PathElement(
                  pathData: PathData.parse(
                    'M 12 10.9 C 12.61 10.9 13.1 11.39 13.1 12 C 13.1 12.61 12.61 13.1 12 13.1 C 11.39 13.1 10.9 12.61 10.9 12 C 10.9 11.39 11.39 10.9 12 10.9 Z',
                  ),
                  fillColor: Color(0xFF000000),
                ),
              ],
            ),
            ClipPathElement(
              pathData: PathData.parse(
                'M 0.188 0.188 L 0.188 24 L 23.938 24 L 23.938 0.188 L 0.188 0.188 Z M 12 10.9 C 12.61 10.9 13.1 11.39 13.1 12 C 13.1 12.61 12.61 13.1 12 13.1 C 11.39 13.1 10.9 12.61 10.9 12 C 10.9 11.39 11.39 10.9 12 10.9 Z',
              ),
            ),
            PathElement(
              pathData: PathData.parse(
                'M 9.99 9.99 C 9.408 11.242 8.827 12.493 8.245 13.745 C 7.663 14.997 7.082 16.248 6.5 17.5 C 6.5 17.5 6.5 17.5 6.5 17.5 C 9.003 16.337 11.507 15.173 14.01 14.01 C 15.173 11.507 16.337 9.003 17.5 6.5 C 14.997 7.663 12.493 8.827 9.99 9.99 M 12 10.9 C 11.39 10.9 10.9 11.39 10.9 12 C 10.9 12.305 11.023 12.58 11.221 12.779 C 11.42 12.977 11.695 13.1 12 13.1 C 12.61 13.1 13.1 12.61 13.1 12 C 13.1 11.39 12.61 10.9 12 10.9 L 12 10.9 M 12 12 L 12 12 L 12 12 L 12 12 L 12 12 L 12 12 L 12 12 M 12 12 L 12 12 C 12 12 12 12 12 12 C 12 12 12 12 12 12 C 12 12 12 12 12 12 C 12 12 12 12 12 12',
              ),
              fillColor: Color(0xFF000000),
              properties: PathAnimationProperties(
                pathData: [
                  AnimationStep(
                    tween: ConstPathDataTween(
                      begin: PathData.parse(
                        'M 9.99 9.99 C 9.408 11.242 8.827 12.493 8.245 13.745 C 7.663 14.997 7.082 16.248 6.5 17.5 C 6.5 17.5 6.5 17.5 6.5 17.5 C 9.003 16.337 11.507 15.173 14.01 14.01 C 15.173 11.507 16.337 9.003 17.5 6.5 C 14.997 7.663 12.493 8.827 9.99 9.99 M 12 10.9 C 11.39 10.9 10.9 11.39 10.9 12 C 10.9 12.305 11.023 12.58 11.221 12.779 C 11.42 12.977 11.695 13.1 12 13.1 C 12.61 13.1 13.1 12.61 13.1 12 C 13.1 11.39 12.61 10.9 12 10.9 L 12 10.9 M 12 12 L 12 12 L 12 12 L 12 12 L 12 12 L 12 12 L 12 12 M 12 12 L 12 12 C 12 12 12 12 12 12 C 12 12 12 12 12 12 C 12 12 12 12 12 12 C 12 12 12 12 12 12',
                      ),
                      end: PathData.parse(
                        'M 12 2 C 6.48 2 2 6.48 2 12 C 2 17.141 5.886 21.38 10.878 21.938 C 11.247 21.979 11.621 22 12 22 C 17.52 22 22 17.52 22 12 C 22 6.48 17.52 2 12 2 C 12 2 12 2 12 2 M 12 10.9 C 11.695 10.9 11.42 11.023 11.221 11.221 C 11.023 11.42 10.9 11.695 10.9 12 C 10.9 12.61 11.39 13.1 12 13.1 C 12.61 13.1 13.1 12.61 13.1 12 C 13.1 11.39 12.61 10.9 12 10.9 L 12 10.9 M 14.19 14.19 L 6 18 L 6 18 L 9.81 9.81 L 18 6 L 14.19 14.19 L 14.19 14.19 M 12 12 L 12 12 C 12 12 12 12 12 12 C 12 12 12 12 12 12 C 12 12 12 12 12 12 C 12 12 12 12 12 12',
                      ),
                    ),
                    interval:
                        AnimationInterval(end: Duration(milliseconds: 300)),
                    curve: Curves.fastOutSlowIn,
                  ),
                ],
              ),
            ),
            GroupElement(
              pivotX: 12,
              pivotY: 12,
              scaleX: 0.833,
              scaleY: 0.833,
              elements: [
                PathElement(
                  pathData: PathData.parse(
                    'M 12 0 C 8.819 0 5.765 1.265 3.515 3.515 C 1.265 5.765 0 8.819 0 12 C 0 15.181 1.265 18.235 3.515 20.485 C 5.765 22.735 8.819 24 12 24 C 15.181 24 18.235 22.735 20.485 20.485 C 22.735 18.235 24 15.181 24 12 C 24 8.819 22.735 5.765 20.485 3.515 C 18.235 1.265 15.181 0 12 0 Z M 12 21.6 C 9.455 21.6 7.012 20.588 5.212 18.788 C 3.412 16.988 2.4 14.545 2.4 12 C 2.4 9.455 3.412 7.012 5.212 5.212 C 7.012 3.412 9.455 2.4 12 2.4 C 14.545 2.4 16.988 3.412 18.788 5.212 C 20.588 7.012 21.6 9.455 21.6 12 C 21.6 14.545 20.588 16.988 18.788 18.788 C 16.988 20.588 14.545 21.6 12 21.6 Z',
                  ),
                  fillColor: Color(0xFF000000),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );

  static const more = AnimatedVectorData(
    viewportSize: Size(1080, 1080),
    duration: Duration(milliseconds: 517),
    root: RootVectorElement(
      elements: [
        PathElement(
          pathData: PathData.parse(
            'M270.46 450.51 C220.99,450.51 180.52,490.99 180.52,540.46 C180.52,589.93 220.99,630.41 270.46,630.41 C319.93,630.41 360.41,589.93 360.41,540.46 C360.41,490.99 319.93,450.51 270.46,450.51',
          ),
          fillColor: Color(0xFF000000),
          properties: PathAnimationProperties(
            pathData: [
              AnimationStep(
                tween: ConstPathDataTween(
                  begin: PathData.parse(
                    'M270.46 450.51 C220.99,450.51 180.52,490.99 180.52,540.46 C180.52,589.93 220.99,630.41 270.46,630.41 C319.93,630.41 360.41,589.93 360.41,540.46 C360.41,490.99 319.93,450.51 270.46,450.51',
                  ),
                  end: PathData.parse(
                    'M272.31 322.51 C222.84,322.51 182.36,362.99 182.36,412.46 C182.36,461.93 222.84,502.41 272.31,502.41 C321.78,502.41 362.26,461.93 362.26,412.46 C362.26,362.99 321.78,322.51 272.31,322.51',
                  ),
                ),
                interval: AnimationInterval(
                  start: Duration(milliseconds: 83),
                  end: Duration(milliseconds: 183),
                ),
                curve: _hopCurve,
              ),
              AnimationStep(
                tween: ConstPathDataTween(
                  begin: PathData.parse(
                    'M272.31 322.51 C222.84,322.51 182.36,362.99 182.36,412.46 C182.36,461.93 222.84,502.41 272.31,502.41 C321.78,502.41 362.26,461.93 362.26,412.46 C362.26,362.99 321.78,322.51 272.31,322.51',
                  ),
                  end: PathData.parse(
                    'M270.46 486.51 C220.99,486.51 180.52,526.99 180.52,576.46 C180.52,625.93 220.99,666.41 270.46,666.41 C319.93,666.41 360.41,625.93 360.41,576.46 C360.41,526.99 319.93,486.51 270.46,486.51',
                  ),
                ),
                interval: AnimationInterval(
                  start: Duration(milliseconds: 183),
                  end: Duration(milliseconds: 316),
                ),
                curve: _hopCurve,
              ),
              AnimationStep(
                tween: ConstPathDataTween(
                  begin: PathData.parse(
                    'M270.46 486.51 C220.99,486.51 180.52,526.99 180.52,576.46 C180.52,625.93 220.99,666.41 270.46,666.41 C319.93,666.41 360.41,625.93 360.41,576.46 C360.41,526.99 319.93,486.51 270.46,486.51',
                  ),
                  end: PathData.parse(
                    'M270.46 450.51 C220.99,450.51 180.52,490.99 180.52,540.46 C180.52,589.93 220.99,630.41 270.46,630.41 C319.93,630.41 360.41,589.93 360.41,540.46 C360.41,490.99 319.93,450.51 270.46,450.51',
                  ),
                ),
                interval: AnimationInterval(
                  start: Duration(milliseconds: 317),
                  end: Duration(milliseconds: 384),
                ),
                curve: _hopCurve,
              ),
            ],
          ),
        ),
        PathElement(
          pathData: PathData.parse(
            'M540.31 450.51 C490.84,450.51 450.36,490.99 450.36,540.46 C450.36,589.93 490.84,630.41 540.31,630.41 C589.78,630.41 630.26,589.93 630.26,540.46 C630.26,490.99 589.78,450.51 540.31,450.51',
          ),
          fillColor: Color(0xFF000000),
          properties: PathAnimationProperties(
            pathData: [
              AnimationStep(
                tween: ConstPathDataTween(
                  begin: PathData.parse(
                    'M540.31 450.51 C490.84,450.51 450.36,490.99 450.36,540.46 C450.36,589.93 490.84,630.41 540.31,630.41 C589.78,630.41 630.26,589.93 630.26,540.46 C630.26,490.99 589.78,450.51 540.31,450.51',
                  ),
                  end: PathData.parse(
                    'M542.16 322.51 C492.68,322.51 452.21,362.99 452.21,412.46 C452.21,461.93 492.68,502.41 542.16,502.41 C591.63,502.41 632.1,461.93 632.1,412.46 C632.1,362.99 591.63,322.51 542.16,322.51',
                  ),
                ),
                interval: AnimationInterval(
                  start: Duration(milliseconds: 150),
                  end: Duration(milliseconds: 250),
                ),
                curve: _hopCurve,
              ),
              AnimationStep(
                tween: ConstPathDataTween(
                  begin: PathData.parse(
                    'M542.16 322.51 C492.68,322.51 452.21,362.99 452.21,412.46 C452.21,461.93 492.68,502.41 542.16,502.41 C591.63,502.41 632.1,461.93 632.1,412.46 C632.1,362.99 591.63,322.51 542.16,322.51',
                  ),
                  end: PathData.parse(
                    'M540.31 486.51 C490.84,486.51 450.36,526.99 450.36,576.46 C450.36,625.93 490.84,666.41 540.31,666.41 C589.78,666.41 630.26,625.93 630.26,576.46 C630.26,526.99 589.78,486.51 540.31,486.51',
                  ),
                ),
                interval: AnimationInterval(
                  start: Duration(milliseconds: 250),
                  end: Duration(milliseconds: 383),
                ),
                curve: _hopCurve,
              ),
              AnimationStep(
                tween: ConstPathDataTween(
                  begin: PathData.parse(
                    'M540.31 486.51 C490.84,486.51 450.36,526.99 450.36,576.46 C450.36,625.93 490.84,666.41 540.31,666.41 C589.78,666.41 630.26,625.93 630.26,576.46 C630.26,526.99 589.78,486.51 540.31,486.51',
                  ),
                  end: PathData.parse(
                    'M540.31 450.51 C490.84,450.51 450.36,490.99 450.36,540.46 C450.36,589.93 490.84,630.41 540.31,630.41 C589.78,630.41 630.26,589.93 630.26,540.46 C630.26,490.99 589.78,450.51 540.31,450.51',
                  ),
                ),
                interval: AnimationInterval(
                  start: Duration(milliseconds: 383),
                  end: Duration(milliseconds: 450),
                ),
                curve: _hopCurve,
              ),
            ],
          ),
        ),
        PathElement(
          pathData: PathData.parse(
            'M810.16 450.51 C760.68,450.51 720.21,490.99 720.21,540.46 C720.21,589.93 760.68,630.41 810.16,630.41 C859.63,630.41 900.1,589.93 900.1,540.46 C900.1,490.99 859.63,450.51 810.16,450.51',
          ),
          fillColor: Color(0xFF000000),
          properties: PathAnimationProperties(
            pathData: [
              AnimationStep(
                tween: ConstPathDataTween(
                  begin: PathData.parse(
                    'M810.16 450.51 C760.68,450.51 720.21,490.99 720.21,540.46 C720.21,589.93 760.68,630.41 810.16,630.41 C859.63,630.41 900.1,589.93 900.1,540.46 C900.1,490.99 859.63,450.51 810.16,450.51',
                  ),
                  end: PathData.parse(
                    'M812 322.51 C762.53,322.51 722.05,362.99 722.05,412.46 C722.05,461.93 762.53,502.41 812,502.41 C861.47,502.41 901.95,461.93 901.95,412.46 C901.95,362.99 861.47,322.51 812,322.51',
                  ),
                ),
                interval: AnimationInterval(
                  start: Duration(milliseconds: 217),
                  end: Duration(milliseconds: 317),
                ),
                curve: _hopCurve,
              ),
              AnimationStep(
                tween: ConstPathDataTween(
                  begin: PathData.parse(
                    'M812 322.51 C762.53,322.51 722.05,362.99 722.05,412.46 C722.05,461.93 762.53,502.41 812,502.41 C861.47,502.41 901.95,461.93 901.95,412.46 C901.95,362.99 861.47,322.51 812,322.51',
                  ),
                  end: PathData.parse(
                    'M810.16 486.51 C760.68,486.51 720.21,526.99 720.21,576.46 C720.21,625.93 760.68,666.41 810.16,666.41 C859.63,666.41 900.1,625.93 900.1,576.46 C900.1,526.99 859.63,486.51 810.16,486.51',
                  ),
                ),
                interval: AnimationInterval(
                  start: Duration(milliseconds: 317),
                  end: Duration(milliseconds: 450),
                ),
                curve: _hopCurve,
              ),
              AnimationStep(
                tween: ConstPathDataTween(
                  begin: PathData.parse(
                    'M810.16 486.51 C760.68,486.51 720.21,526.99 720.21,576.46 C720.21,625.93 760.68,666.41 810.16,666.41 C859.63,666.41 900.1,625.93 900.1,576.46 C900.1,526.99 859.63,486.51 810.16,486.51',
                  ),
                  end: PathData.parse(
                    'M810.16 450.51 C760.68,450.51 720.21,490.99 720.21,540.46 C720.21,589.93 760.68,630.41 810.16,630.41 C859.63,630.41 900.1,589.93 900.1,540.46 C900.1,490.99 859.63,450.51 810.16,450.51',
                  ),
                ),
                interval: AnimationInterval(
                  start: Duration(milliseconds: 450),
                  end: Duration(milliseconds: 517),
                ),
                curve: _hopCurve,
              ),
            ],
          ),
        ),
      ],
    ),
  );

  // Original (no Komikku reference — they have no Downloads tab): the arrow
  // lifts out of the tray and drops back with a small overshoot. Glyph is the
  // Material file_download outlined 24px SVG, split into arrow and tray.
  static const downloads = AnimatedVectorData(
    viewportSize: Size(24, 24),
    duration: Duration(milliseconds: 300),
    root: RootVectorElement(
      elements: [
        PathElement(
          pathData: PathData.parse(
            'M18,15v3H6v-3H4v3c0,1.1,0.9,2,2,2h12c1.1,0,2-0.9,2-2v-3H18z',
          ),
          fillColor: Color(0xFF000000),
        ),
        GroupElement(
          properties: GroupAnimationProperties(
            translateY: [
              AnimationStep(
                tween: ConstTween(begin: 0, end: -2.5),
                interval: AnimationInterval(end: Duration(milliseconds: 100)),
                curve: Curves.fastOutSlowIn,
              ),
              AnimationStep(
                tween: ConstTween(begin: -2.5, end: 1),
                interval: AnimationInterval(
                  start: Duration(milliseconds: 100),
                  end: Duration(milliseconds: 220),
                ),
                curve: Curves.fastOutSlowIn,
              ),
              AnimationStep(
                tween: ConstTween(begin: 1, end: 0),
                interval: AnimationInterval(
                  start: Duration(milliseconds: 220),
                  end: Duration(milliseconds: 300),
                ),
                curve: Curves.fastOutSlowIn,
              ),
            ],
          ),
          elements: [
            PathElement(
              pathData: PathData.parse(
                'M17,11l-1.41-1.41L13,12.17V4h-2v8.17L8.41,9.59L7,11l5,5 L17,11z',
              ),
              fillColor: Color(0xFF000000),
            ),
          ],
        ),
      ],
    ),
  );
}
