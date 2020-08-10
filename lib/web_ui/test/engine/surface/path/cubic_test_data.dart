// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';
import 'package:ui/ui.dart' hide window;
import 'package:ui/src/engine.dart';

const double D = kFltEpsilon / 2;
const double G = kFltEpsilon / 3;
const double N = -kFltEpsilon / 2;
const double M = -kFltEpsilon / 3;
const double E = kFltEpsilon * 8;
const double F = kFltEpsilon * 8;

const List<List<Offset>> pointDegenerates = [
  [Offset(0, 0), Offset(0, 0), Offset(0, 0), Offset(0, 0)],
  [Offset(1, 1), Offset(1, 1), Offset(1, 1), Offset(1, 1)],
  [Offset(1 + kFltEpsilonHalf, 1), Offset(1, 1 + kFltEpsilonHalf), Offset(1, 1), Offset(1, 1)],
  [Offset(1 + D, 1), Offset(1 - D, 1), Offset(1, 1), Offset(1, 1)],
  [Offset(0, 0), Offset(0, 0), Offset(1, 0), Offset(0, 0)],
  [Offset(0, 0), Offset(1, 0), Offset(0, 0), Offset(0, 0)],
  [Offset(0, 0), Offset(0, 0), Offset(0, 1), Offset(0, 0)],
  [Offset(0, 0), Offset(0, 1), Offset(0, 0), Offset(0, 0)],
  [Offset(0, 0), Offset(0, 0), Offset(1, 1), Offset(0, 0)],
  [Offset(0, 0), Offset(1, 1), Offset(0, 0), Offset(0, 0)],
  [Offset(0, 0), Offset(1, 1), Offset(2, 2), Offset(0, 0)],
  [Offset(1, 1), Offset(2, 2), Offset(2, 2), Offset(1, 1)],
  [Offset(0, 0), Offset(0, D), Offset(1, 0), Offset(0, 0)],
  [Offset(0, 0), Offset(1, 0), Offset(0, D), Offset(0, 0)],
  [Offset(0, 0), Offset(D, 0), Offset(0, 1), Offset(0, 0)],
  [Offset(0, 0), Offset(0, 1), Offset(D, 0), Offset(0, 0)],
  [Offset(1, 1), Offset(2, 2), Offset(2, 2+D), Offset(1, 1)],
  [Offset(0, 0), Offset(0, N), Offset(1, 0), Offset(0, 0)],
  [Offset(0, 0), Offset(1, 0), Offset(0, N), Offset(0, 0)],
  [Offset(0, 0), Offset(N, 0), Offset(0, 1), Offset(0, 0)],
  [Offset(0, 0), Offset(0, 1), Offset(N, 0), Offset(0, 0)],
  [Offset(0, 0), Offset(1, 1), Offset(N, 0), Offset(0, 0)],
  [Offset(0, 0), Offset(D, 0), Offset(1, 1), Offset(0, 0)],
  [Offset(0, 0), Offset(1, 1), Offset(D, 0), Offset(0, 0)],
  [Offset(0, 0), Offset(N, 0), Offset(1, 1), Offset(0, 0)],
  [Offset(1, 1), Offset(2, 2), Offset(2, 2 + N), Offset(1, 1)],
];

int pointDegeneratesCount = pointDegenerates.length;

const List<List<Offset>> notPointDegenerates = [
  [Offset(1 + kFltEpsilon * 8, 1), Offset(1, kFltEpsilon * 8), Offset(1, 1), Offset(1, 1)],
  [Offset(1 + kFltEpsilon * 8, 1), Offset(1 - kFltEpsilon * 8, 1), Offset(1, 1), Offset(1, 1)],
];

int notPointDegeneratesCount = notPointDegenerates.length;

/// Source: http://www.truetex.com/bezint.htm
const List<List<Offset>> testPoints = [
  // intersects in one place (data gives bezier clip fits
  [Offset(0, 45), Offset(6.0094158284751593, 51.610357411322688),
    Offset(12.741093228940867, 55.981703949474607),
    Offset(20.021417396476362, 58.652245509710262)],
  [Offset(2.2070737699246674, 52.703494107327209),
    Offset(31.591482272629477, 23.811002295222025),
    Offset(76.82488616426425, 44.049473790502674),
    Offset(119.25488947221436, 55.599248272955073)],
  // intersects in three places
  [Offset(0, 45), Offset(50, 100), Offset(150,   0), Offset(200, 55)],
  [Offset(0, 55), Offset(50,   0), Offset(150, 100), Offset(200, 45)],
  // intersects in one place, cross over is nearly parallel
  [Offset(0,   0), Offset(0, 100), Offset(200,   0), Offset(200, 100)],
  [Offset(0, 100), Offset(0,   0), Offset(200, 100), Offset(200,   0)],
  // intersects in two places
  [Offset(0,   0), Offset(0, 100), Offset(200, 100), Offset(200,   0)],
  [Offset(0, 100), Offset(0,   0), Offset(200,   0), Offset(200, 100)],
  [Offset(150, 100), Offset(150 + 0.1, 150), Offset(150, 200), Offset(150, 250)],
  [Offset(250, 150), Offset(200, 150 + 0.1), Offset(150, 150), Offset(100, 150)],
  // single intersection around 168,185
  [Offset(200, 100), Offset(150, 100), Offset(150, 150), Offset(200, 150)],
  [Offset(250, 150), Offset(250, 100), Offset(100, 100), Offset(100, 150)],
  [Offset(1.0, 1.5), Offset(15.5, 0.5), Offset(-8.0, 3.5), Offset(5.0, 1.5)],
  [Offset(4.0, 0.5), Offset(5.0, 15.0), Offset(2.0, -8.5), Offset(4.0, 4.5)],
  [Offset(664.00168, 0), Offset(726.11545, 124.22757),
    Offset(736.89069, 267.89743), Offset(694.0017, 400.0002)],
  [Offset(850.66843, 115.55563), Offset(728.515, 115.55563),
    Offset(725.21347, 275.15309), Offset(694.0017, 400.0002)],
  [Offset(1, 1), Offset(12.5, 6.5), Offset(-4, 6.5), Offset(7.5, 1)],
  [Offset(1, 6.5), Offset(12.5, 1), Offset(-4, 1), Offset(.5, 6)],
  [Offset(315.748, 312.84), Offset(312.644, 318.134),
    Offset(305.836, 319.909), Offset(300.542, 316.804)],
  [Offset(317.122, 309.05), Offset(316.112, 315.102),
    Offset(310.385, 319.19),  Offset(304.332, 318.179)],
  [Offset(1046.604051, 172.937967),  Offset(1046.604051, 178.9763059),
    Offset(1041.76745,  183.9279165), Offset(1035.703842, 184.0432409)],
  [Offset(1046.452235, 174.7640504), Offset(1045.544872, 180.1973817),
    Offset(1040.837966, 184.0469882), Offset(1035.505925, 184.0469882)],
  [Offset(125.79356, 199.57382), Offset(51.16556, 128.93575),
    Offset(87.494,  16.67848), Offset(167.29361, 16.67848)],
  [Offset(167.29361, 55.81876), Offset(100.36128, 55.81876),
    Offset(68.64099, 145.4755), Offset(125.7942, 199.57309)],
  [Offset(104.11546583642826, 370.21352558595504),
    Offset(122.96968232592344, 404.54489231839295),
    Offset(169.90881005384728, 425.00067000000007),
    Offset(221.33045999999999, 425.00067000000001)],
  [Offset(116.32365976159625, 381.71048540582598),
    Offset(103.86096590870899, 381.71048540581626),
    Offset(91.394188003200725, 377.17917781762833),
    Offset(82.622283093355179, 368.11683661930334)],
];

int testPointsCount = testPoints.length;

const List<List<Offset>> cubicLines = [
  [Offset(0, 0), Offset(0, 0), Offset(0, 0), Offset(1, 0)],  // 0: horizontal
  [Offset(1, 0), Offset(0, 0), Offset(0, 0), Offset(0, 0)],
  [Offset(1, 0), Offset(2, 0), Offset(3, 0), Offset(4, 0)],
  [Offset(0, 0), Offset(0, 0), Offset(0, 0), Offset(0, 1)],  // 5: vertical
  [Offset(0, 1), Offset(0, 0), Offset(0, 0), Offset(0, 0)],
  [Offset(0, 1), Offset(0, 2), Offset(0, 3), Offset(0, 4)],
  [Offset(0, 0), Offset(0, 0), Offset(0, 0), Offset(1, 1)],  // 10: 3 coincident
  [Offset(1, 1), Offset(0, 0), Offset(0, 0), Offset(0, 0)],
  [Offset(0, 0), Offset(0, 0), Offset(1, 1), Offset(2, 2)],  // 14: 2 coincident
  [Offset(0, 0), Offset(1, 1), Offset(0, 0), Offset(2, 2)],
  [Offset(1, 1), Offset(0, 0), Offset(0, 0), Offset(2, 2)],  // 17:
  [Offset(1, 1), Offset(0, 0), Offset(2, 2), Offset(0, 0)],
  [Offset(1, 1), Offset(2, 2), Offset(0, 0), Offset(0, 0)],
  [Offset(1, 1), Offset(2, 2), Offset(3, 3), Offset(2, 2)],  // middle-last coincident
  [Offset(1, 1), Offset(2, 2), Offset(3, 3), Offset(3, 3)],  // middle-last coincident
  [Offset(1, 1), Offset(1, 1), Offset(2, 2), Offset(2, 2)],  // 2 pairs coincident
  [Offset(1, 1), Offset(2, 2), Offset(1, 1), Offset(2, 2)],
  [Offset(1, 1), Offset(1, 1), Offset(3, 3), Offset(3, 3)],  // first-middle middle-last coincident
  [Offset(1, 1), Offset(2, 2), Offset(3, 3), Offset(4, 4)],  // no coincident
  [Offset(1, 1), Offset(3, 3), Offset(2, 2), Offset(4, 4)],
  [Offset(1, 1), Offset(2, 2), Offset(4, 4), Offset(3, 3)],
  [Offset(1, 1), Offset(3, 3), Offset(4, 4), Offset(2, 2)],
  [Offset(1, 1), Offset(4, 4), Offset(2, 2), Offset(3, 3)],
  [Offset(1, 1), Offset(4, 4), Offset(3, 3), Offset(2, 2)],
  [Offset(2, 2), Offset(1, 1), Offset(3, 3), Offset(4, 4)],
  [Offset(2, 2), Offset(1, 1), Offset(4, 4), Offset(3, 3)],
  [Offset(2, 2), Offset(3, 3), Offset(1, 1), Offset(4, 4)],
  [Offset(2, 2), Offset(3, 3), Offset(4, 4), Offset(1, 1)],
  [Offset(2, 2), Offset(4, 4), Offset(1, 1), Offset(3, 3)],
  [Offset(2, 2), Offset(4, 4), Offset(3, 3), Offset(1, 1)],
];

int cubicLinesCount = cubicLines.length;

// 'not a line' tries to fool the line detection code
const List<List<Offset>> notLines = [
  [Offset(0, 0), Offset(0, 0), Offset(0, 1), Offset(1, 0)],
  [Offset(0, 0), Offset(0, 1), Offset(0, 0), Offset(1, 0)],
  [Offset(0, 0), Offset(0, 1), Offset(1, 0), Offset(0, 0)],
  [Offset(0, 1), Offset(0, 0), Offset(0, 0), Offset(1, 0)],
  [Offset(0, 1), Offset(0, 0), Offset(1, 0), Offset(0, 0)],
  [Offset(0, 1), Offset(1, 0), Offset(0, 0), Offset(0, 0)],
];

int notLinesCount = notLines.length;

const List<List<Offset>> modEpsilonLines = [
  [Offset(0, E), Offset(0, 0), Offset(0, 0), Offset(1, 0)],  // horizontal
  [Offset(0, 0), Offset(0, E), Offset(1, 0), Offset(0, 0)],
  [Offset(0, 0), Offset(1, 0), Offset(0, E), Offset(0, 0)],
  [Offset(1, 0), Offset(0, 0), Offset(0, 0), Offset(0, E)],
  [Offset(1, E), Offset(2, 0), Offset(3, 0), Offset(4, 0)],
  [Offset(E, 0), Offset(0, 0), Offset(0, 0), Offset(0, 1)],  // vertical
  [Offset(0, 0), Offset(E, 0), Offset(0, 1), Offset(0, 0)],
  [Offset(0, 0), Offset(0, 1), Offset(E, 0), Offset(0, 0)],
  [Offset(0, 1), Offset(0, 0), Offset(0, 0), Offset(E, 0)],
  [Offset(E, 1), Offset(0, 2), Offset(0, 3), Offset(0, 4)],
  [Offset(E, 0), Offset(0, 0), Offset(0, 0), Offset(1, 1)],  // 3 coincident
  [Offset(0, 0), Offset(E, 0), Offset(1, 1), Offset(0, 0)],
  [Offset(0, 0), Offset(1, 1), Offset(E, 0), Offset(0, 0)],
  [Offset(1, 1), Offset(0, 0), Offset(0, 0), Offset(E, 0)],
  [Offset(0, E), Offset(0, 0), Offset(1, 1), Offset(2, 2)],  // 2 coincident
  [Offset(0, 0), Offset(1, 1), Offset(0, E), Offset(2, 2)],
  [Offset(0, 0), Offset(1, 1), Offset(2, 2), Offset(0, E)],
  [Offset(1, 1), Offset(0, E), Offset(0, 0), Offset(2, 2)],
  [Offset(1, 1), Offset(0, E), Offset(2, 2), Offset(0, 0)],
  [Offset(1, 1), Offset(2, 2), Offset(E, 0), Offset(0, 0)],
  [Offset(1, 1), Offset(2, 2+E), Offset(3, 3), Offset(2, 2)],  // middle-last coincident
  [Offset(1, 1), Offset(2+E, 2), Offset(3, 3), Offset(3, 3)],  // middle-last coincident
  [Offset(1, 1), Offset(1, 1), Offset(2, 2), Offset(2+E, 2)],  // 2 pairs coincident
  [Offset(1, 1), Offset(2, 2), Offset(1, 1), Offset(2+E, 2)],
  [Offset(1, 1), Offset(2, 2), Offset(2, 2+E), Offset(1, 1)],
  [Offset(1, 1), Offset(1, 1+E), Offset(3, 3), Offset(3, 3)],  // first-middle middle-last coincident
  [Offset(1, 1), Offset(2+E, 2), Offset(3, 3), Offset(4, 4)],  // no coincident
  [Offset(1, 1), Offset(3, 3), Offset(2, 2), Offset(4, 4+F+F)],  // INVESTIGATE: why the epsilon is bigger
  [Offset(1, 1+F+F), Offset(2, 2), Offset(4, 4), Offset(3, 3)],  // INVESTIGATE: why the epsilon is bigger
  [Offset(1, 1), Offset(3, 3), Offset(4, 4+E), Offset(2, 2)],
  [Offset(1, 1), Offset(4, 4), Offset(2, 2), Offset(3, 3+E)],
  [Offset(1, 1), Offset(4, 4), Offset(3, 3), Offset(2+E, 2)],
  [Offset(2, 2), Offset(1, 1), Offset(3+E, 3), Offset(4, 4)],
  [Offset(2, 2), Offset(1+E, 1), Offset(4, 4), Offset(3, 3)],
  [Offset(2, 2+E), Offset(3, 3), Offset(1, 1), Offset(4, 4)],
  [Offset(2+E, 2), Offset(3, 3), Offset(4, 4), Offset(1, 1)],
  [Offset(2, 2), Offset(4+E, 4), Offset(1, 1), Offset(3, 3)],
  [Offset(2, 2), Offset(4, 4), Offset(3, 3), Offset(1, 1+E)],
];

int modEpsilonLinesCount = modEpsilonLines.length;

const List<List<Offset>> lessEpsilonLines = [
  [Offset(0, D), Offset(0, 0), Offset(0, 0), Offset(1, 0)],  // horizontal
  [Offset(1, 0), Offset(0, 0), Offset(0, 0), Offset(0, D)],
  [Offset(1, D), Offset(2, 0), Offset(3, 0), Offset(4, 0)],
  [Offset(D, 0), Offset(0, 0), Offset(0, 0), Offset(0, 1)],  // vertical
  [Offset(0, 1), Offset(0, 0), Offset(0, 0), Offset(D, 0)],
  [Offset(D, 1), Offset(0, 2), Offset(0, 3), Offset(0, 4)],
  [Offset(D, 0), Offset(0, 0), Offset(0, 0), Offset(1, 1)],  // 3 coincident
  [Offset(1, 1), Offset(0, 0), Offset(0, 0), Offset(D, 0)],
  [Offset(0, D), Offset(0, 0), Offset(1, 1), Offset(2, 2)],  // 2 coincident
  [Offset(0, 0), Offset(1, 1), Offset(0, D), Offset(2, 2)],
  [Offset(0, 0), Offset(1, 1), Offset(2, 2), Offset(1, 1+D)],
  [Offset(1, 1), Offset(0, D), Offset(0, 0), Offset(2, 2)],
  [Offset(1, 1), Offset(0, D), Offset(2, 2), Offset(0, 0)],
  [Offset(1, 1), Offset(2, 2), Offset(D, 0), Offset(0, 0)],
  [Offset(1, 1), Offset(2, 2+D), Offset(3, 3), Offset(2, 2)],  // middle-last coincident
  [Offset(1, 1), Offset(2+D, 2), Offset(3, 3), Offset(3, 3)],  // middle-last coincident
  [Offset(1, 1), Offset(1, 1), Offset(2, 2), Offset(2+D, 2)],  // 2 pairs coincident
  [Offset(1, 1), Offset(2, 2), Offset(1, 1), Offset(2+D, 2)],
  [Offset(1, 1), Offset(1, 1+D), Offset(3, 3), Offset(3, 3)],  // first-middle middle-last coincident
  [Offset(1, 1), Offset(2+D/2, 2), Offset(3, 3), Offset(4, 4)],  // no coincident
  [Offset(1, 1), Offset(3, 3), Offset(2, 2), Offset(4, 4+D)],
  [Offset(1, 1+D), Offset(2, 2), Offset(4, 4), Offset(3, 3)],
  [Offset(1, 1), Offset(3, 3), Offset(4, 4+D), Offset(2, 2)],
  [Offset(1, 1), Offset(4, 4), Offset(2, 2), Offset(3, 3+D)],
  [Offset(1, 1), Offset(4, 4), Offset(3, 3), Offset(2+G, 2)],  // INVESTIGATE: why the epsilon is smaller
  [Offset(2, 2), Offset(1, 1), Offset(3+D, 3), Offset(4, 4)],
  [Offset(2, 2), Offset(1+D, 1), Offset(4, 4), Offset(3, 3)],
  [Offset(2, 2+D), Offset(3, 3), Offset(1, 1), Offset(4, 4)],
  [Offset(2+G, 2), Offset(3, 3), Offset(4, 4), Offset(1, 1)],  // INVESTIGATE: why the epsilon is smaller
  [Offset(2, 2), Offset(4+D, 4), Offset(1, 1), Offset(3, 3)],
  [Offset(2, 2), Offset(4, 4), Offset(3, 3), Offset(1, 1+D)],
];

int lessEpsilonLinesCount = lessEpsilonLines.length;

const List<List<Offset>> negEpsilonLines = [
  [Offset(0, N), Offset(0, 0), Offset(0, 0), Offset(1, 0)],  // horizontal
  [Offset(1, 0), Offset(0, 0), Offset(0, 0), Offset(0, N)],
  [Offset(1, N), Offset(2, 0), Offset(3, 0), Offset(4, 0)],
  [Offset(N, 0), Offset(0, 0), Offset(0, 0), Offset(0, 1)],  // vertical
  [Offset(0, 1), Offset(0, 0), Offset(0, 0), Offset(N, 0)],
  [Offset(N, 1), Offset(0, 2), Offset(0, 3), Offset(0, 4)],
  [Offset(N, 0), Offset(0, 0), Offset(0, 0), Offset(1, 1)],  // 3 coincident
  [Offset(1, 1), Offset(0, 0), Offset(0, 0), Offset(N, 0)],
  [Offset(0, N), Offset(0, 0), Offset(1, 1), Offset(2, 2)],  // 2 coincident
  [Offset(0, 0), Offset(1, 1), Offset(0, N), Offset(2, 2)],
  [Offset(0, 0), Offset(1, 1), Offset(2, 2), Offset(1, 1+N)],
  [Offset(1, 1), Offset(0, N), Offset(0, 0), Offset(2, 2)],
  [Offset(1, 1), Offset(0, N), Offset(2, 2), Offset(0, 0)],
  [Offset(1, 1), Offset(2, 2), Offset(N, 0), Offset(0, 0)],
  [Offset(1, 1), Offset(2, 2+N), Offset(3, 3), Offset(2, 2)],  // middle-last coincident
  [Offset(1, 1), Offset(2+N, 2), Offset(3, 3), Offset(3, 3)],  // middle-last coincident
  [Offset(1, 1), Offset(1, 1), Offset(2, 2), Offset(2+N, 2)],  // 2 pairs coincident
  [Offset(1, 1), Offset(2, 2), Offset(1, 1), Offset(2+N, 2)],
  [Offset(1, 1), Offset(1, 1+N), Offset(3, 3), Offset(3, 3)],  // first-middle middle-last coincident
  [Offset(1, 1), Offset(2+N/2, 2), Offset(3, 3), Offset(4, 4)],  // no coincident
  [Offset(1, 1), Offset(3, 3), Offset(2, 2), Offset(4, 4+N)],
  [Offset(1, 1+N), Offset(2, 2), Offset(4, 4), Offset(3, 3)],
  [Offset(1, 1), Offset(3, 3), Offset(4, 4+N), Offset(2, 2)],
  [Offset(1, 1), Offset(4, 4), Offset(2, 2), Offset(3, 3+N)],
  [Offset(1, 1), Offset(4, 4), Offset(3, 3), Offset(2+M, 2)],  // INVESTIGATE: why the epsilon is smaller
  [Offset(2, 2), Offset(1, 1), Offset(3+N, 3), Offset(4, 4)],
  [Offset(2, 2), Offset(1+N, 1), Offset(4, 4), Offset(3, 3)],
  [Offset(2, 2+N), Offset(3, 3), Offset(1, 1), Offset(4, 4)],
  [Offset(2+M, 2), Offset(3, 3), Offset(4, 4), Offset(1, 1)],  // INVESTIGATE: why the epsilon is smaller
  [Offset(2, 2), Offset(4+N, 4), Offset(1, 1), Offset(3, 3)],
  [Offset(2, 2), Offset(4, 4), Offset(3, 3), Offset(1, 1+N)],
];

int negEpsilonLinesCount = negEpsilonLines.length;

/// Helper function to convert list of offsets to typed array.
Float32List offsetListToPoints(List<Offset> offsets) {
  Float32List points = Float32List(offsets.length * 2);
  int pointIndex = 0;
  for (int p = 0; p < offsets.length; p++) {
    points[pointIndex++] = offsets[p].dx;
    points[pointIndex++] = offsets[p].dy;
  }
  return points;
}
