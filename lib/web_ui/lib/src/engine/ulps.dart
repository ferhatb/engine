// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10
part of engine;

// This is a small library to handle stability for floating point operations.
//
// Since we are representing an infinite number of real numbers in finite
// number of bits, when we perform comparisons of coordinates for paths for
// example, we want to make sure that line and curve sections that are too
// close to each other (number of floating point numbers
// representable in bits between two numbers) are handled correctly and
// don't cause algorithms to fail when we perform operations such as
// subtraction or between checks.
//
// Small introduction into floating point comparison:
//
// For some good articles on the topic, see
// https://randomascii.wordpress.com/category/floating-point/page/2/
// Port based on:
// https://github.com/google/skia/blob/master/include/private/SkFloatBits.h
//
// Here is the 32 bit IEEE representation:
//   uint32_t mantissa : 23;
//   uint32_t exponent : 8;
//   uint32_t sign : 1;
// As you can see it was carefully designed to be reinterpreted as an integer.
//
// Ulps stands for unit in the last place. ulp(x) is the gap between two
// floating point numbers nearest x.

/// Converts a sign-bit int (float interpreted as int) into a 2s complement
/// int. Also converts 0x80000000 to 0. Allows result to be compared using
/// int comparison.
int signBitTo2sCompliment(int x) =>
    (x & 0x80000000) != 0 ? (-(x & 0x7fffffff)) : x;

/// Convert a 2s complement int to a sign-bit (i.e. int interpreted as float).
int twosComplimentToSignBit(int x) {
  if ((x & 0x80000000) == 0) {
    return x;
  }
  x = ~x + 1;
  x |= 0x80000000;
  return x;
}

class _FloatBitConverter {
  final Float32List float32List;
  final Int32List int32List;
  _FloatBitConverter._(this.float32List, this.int32List);

  factory _FloatBitConverter() {
    Float32List float32List = Float32List(1);
    return _FloatBitConverter._(
        float32List, float32List.buffer.asInt32List(0, 1));
  }

  int toInt(Float32List source, int index) {
    float32List[0] = source[index];
    return int32List[0];
  }

  int toBits(double x) {
    float32List[0] = x;
    return int32List[0];
  }

  double toDouble(int bits) {
    int32List[0] = bits;
    return float32List[0];
  }
}

class _DoubleBitConverter {
  final ByteData arrayBuffer = ByteData(8);
  set highBits(int value) {
    arrayBuffer.setUint32(4, value, Endian.little);
  }
  int get highBits => arrayBuffer.getUint32(4, Endian.little);

  set lowBits(int value) {
    arrayBuffer.setUint32(0, value, Endian.little);
  }
  int get lowBits => arrayBuffer.getUint32(0, Endian.little);

  set value(double value) {
    arrayBuffer.setFloat64(0, value, Endian.little);
  }

  double get value => arrayBuffer.getFloat64(0, Endian.little);
}

// Singleton bit converter to prevent typed array allocations.
final _FloatBitConverter _floatBitConverter = _FloatBitConverter();

// Converts float to bits.
int float2Bits(Float32List source, int index) {
  return _floatBitConverter.toInt(source, index);
}

// Converts bits to float.
double bitsToFloat(int bits) {
  return _floatBitConverter.toDouble(bits);
}

const int floatBitsExponentMask = 0x7F800000;
const int floatBitsMatissaMask = 0x007FFFFF;

/// Returns a float as 2s complement int to be able to compare floats to each
/// other.
int floatFromListAs2sCompliment(Float32List source, int index) =>
    signBitTo2sCompliment(float2Bits(source, index));

int floatAs2sCompliment(double x) =>
    signBitTo2sCompliment(_floatBitConverter.toBits(x));

double twosComplimentAsFloat(int x) => bitsToFloat(twosComplimentToSignBit(x));

bool _argumentsDenormalized(double a, double b, int epsilon) {
  double denormalizedCheck = kFltEpsilon * epsilon / 2;
  return a.abs() <= denormalizedCheck && b.abs() <= denormalizedCheck;
}

/// Returns true if values at float precision are equal.
bool equalAsFloats(double a, double b) =>
  _floatBitConverter.toBits(a) == _floatBitConverter.toBits(b);

bool equalUlps(double a, double b, int epsilon, int depsilon) {
  if (_argumentsDenormalized(a, b, depsilon)) {
    return true;
  }
  int aBits = floatAs2sCompliment(a);
  int bBits = floatAs2sCompliment(b);
  // Find the difference in ULPs.
  return aBits < bBits + epsilon && bBits < aBits + epsilon;
}

bool lessUlps(double a, double b, int epsilon) {
  if (_argumentsDenormalized(a, b, epsilon)) {
    return a <= b - kFltEpsilon * epsilon;
  }
  int aBits = floatAs2sCompliment(a);
  int bBits = floatAs2sCompliment(b);
  // Find the difference in ULPs.
  return aBits <= bBits - epsilon;
}

bool lessOrEqualUlps(double a, double b, int epsilon) {
  if (_argumentsDenormalized(a, b, epsilon)) {
    return a < b + kFltEpsilon * epsilon;
  }
  int aBits = floatAs2sCompliment(a);
  int bBits = floatAs2sCompliment(b);
  // Find the difference in ULPs.
  return aBits < bBits + epsilon;
}

/// General equality check that covers between, product and division by using
/// ulps epsilon 16.
bool almostEqualUlps(double a, double b) {
  const int kUlpsEpsilon = 16;
  return equalUlps(a, b, kUlpsEpsilon, kUlpsEpsilon);
}

bool notAlmostEqualUlpsPin(double a, double b) {
  const int kUlpsEpsilon = 16;
  return !equalUlpsPin(a, b, kUlpsEpsilon, kUlpsEpsilon);
}

/// Equality using the same error term for between comparison.
bool almostBequalUlps(double a, double b) {
  const int kUlpsEpsilon = 2;
  return equalUlps(a, b, kUlpsEpsilon, kUlpsEpsilon);
}

/// Equality check for product.
bool almostPequalUlps(double a, double b) {
  const int kUlpsEpsilon = 8;
  return equalUlps(a, b, kUlpsEpsilon, kUlpsEpsilon);
}

/// Equality check for division.
bool almostDequalUlps(double a, double b) {
  const int kUlpsEpsilon = 16;
  return equalUlps(a, b, kUlpsEpsilon, kUlpsEpsilon);
}

bool almostLessUlps(double a, double b) {
  const int kUlpsEpsilon = 16;
  return lessUlps(a, b, kUlpsEpsilon);
}

bool almostLessOrEqualUlps(double a, double b) {
  const int kUlpsEpsilon = 16;
  return lessOrEqualUlps(a, b, kUlpsEpsilon);
}

/// Checks if 2 double points are roughly equal (ulp 256) to each other.
bool approximatelyEqualD(double ax, double ay, double bx, double by) {
  if (approximatelyEqualT(ax, bx) && approximatelyEqualT(ay, by)) {
    return true;
  }
  if (!roughlyEqualUlps(ax, bx) || !roughlyEqualUlps(ay, by)) {
    return false;
  }
  final double dx = (ax - bx);
  final double dy = (ay - by);
  double dist = math.sqrt(distanceSquared(ax, ay, bx, by));
  double tiniest = math.min(math.min(math.min(ax, bx), ay), by);
  double largest = math.max(math.max(math.max(ax, bx), ay), by);
  largest = math.max(largest, -tiniest);
  return almostDequalUlps(largest, largest + dist);
}

/// Checks if 2 points are roughly equal (ulp 256) to each other.
bool approximatelyEqual(double ax, double ay, double bx, double by) {
  if (approximatelyEqualT(ax, bx) && approximatelyEqualT(ay, by)) {
    return true;
  }
  if (!roughlyEqualUlps(ax, bx) || !roughlyEqualUlps(ay, by)) {
    return false;
  }
  final double dx = (ax - bx);
  final double dy = (ay - by);
  double dist = math.sqrt(distanceSquared(ax, ay, bx, by));
  double tiniest = math.min(math.min(math.min(ax, bx), ay), by);
  double largest = math.max(math.max(math.max(ax, bx), ay), by);
  largest = math.max(largest, -tiniest);
  return almostPequalUlps(largest, largest + dist);
}

/// Equality check for comparing curve T values in the range of 0 to 1.
///
/// For general numbers (larger and smaller) use
/// AlmostEqualUlps instead.
bool approximatelyEqualT(double t1, double t2) {
  return approximatelyZero(t1 - t2);
}

bool approximatelyEqualHalf(double x, double y) {
  return approximatelyZeroHalf(x - y);
}

bool approximatelyZeroHalf(double x) => x.abs() < kFltEpsilonHalf;

bool approximatelyZero(double value) => value.abs() < kFltEpsilon;

bool approximatelyZeroInverse(double x) => x.abs() > kFltEpsilonInverse;

bool approximatelyZeroCubed(double x) => x.abs() < kFltEpsilonCubed;

bool approximatelyZeroOrMore(double x) => x > -kFltEpsilon;

bool approximatelyLessThanZero(double x) => x < kFltEpsilon;

bool approximatelyOneOrLess(double x) => x < 1 + kFltEpsilon;

bool approximatelyGreaterThanOne(double x) => x > 1 - kFltEpsilon;

bool roughlyNegative(double x) => x < kRoughEpsilon;

bool roughlyBetween(double a, double b, double c) =>
  a <= c ? roughlyNegative(a - b) && roughlyNegative(b - c)
      : roughlyNegative(b - a) && roughlyNegative(c - b);


bool roughlyEqual(double x, double y) {
  return (x - y).abs() < kRoughEpsilon;
}

bool roughlyEqualUlps(double a, double b) {
  const int kUlpsEpsilon = 256;
  const int kDUlpsEpsilon = 1024;
  return equalUlps(a, b, kUlpsEpsilon, kDUlpsEpsilon);
}

bool moreRoughlyEqual(double x, double y) => (x - y).abs() < kMoreRoughEpsilon;

bool zeroOrOne(double x) => x == 0 || x == 1;

bool preciselyZero(double x) => x.abs() < kDblEpsilonErr;

bool preciselyEqual(double x, double y) => preciselyZero(x - y);

bool dEqualUlpsEpsilon(double a, double b, int epsilon) {
  int aBits = floatAs2sCompliment(a);
  int bBits = floatAs2sCompliment(b);
  // Find the difference in ULPs.
  return aBits < bBits + epsilon && bBits < aBits + epsilon;
}

// Checks equality for division.
bool almostDequalUlpsDouble(double a, double b) {
  final double absA = a.abs();
  final double absB = b.abs();
  if (absA < kScalarMax && absB < kScalarMax) {
    return almostDequalUlps(a, b);
  }
  return (a - b).abs() / math.max(absA, absB) < kDblEpsilonSubdivideErr;
}

bool almostEqualUlpsPin(double a, double b) {
  const int kUlpsEpsilon = 16;
  return equalUlpsPin(a, b, kUlpsEpsilon, kUlpsEpsilon);
}

bool argumentsDenormalized(double a, double b, int epsilon) {
  final double denormalizedCheck = kFltEpsilon * epsilon / 2;
  return a.abs() <= denormalizedCheck && b.abs() <= denormalizedCheck;
}

bool equalUlpsPin(double a, double b, int epsilon, int depsilon) {
  if (!a.isFinite || !b.isFinite) {
    return false;
  }
  if (argumentsDenormalized(a, b, depsilon)) {
    return true;
  }
  int aBits = floatAs2sCompliment(a);
  int bBits = floatAs2sCompliment(b);
  // Find the difference in ULPs.
  return aBits < bBits + epsilon && bBits < aBits + epsilon;
}

bool dNotEqualUlps(double a, double b, int epsilon) {
  int aBits = floatAs2sCompliment(a);
  int bBits = floatAs2sCompliment(b);
  // Find the difference in ULPs.
  return aBits >= bBits + epsilon || bBits >= aBits + epsilon;
}

bool notAlmostDequalUlps(double a, double b) {
  const int kUlpsEpsilon = 16;
  return dNotEqualUlps(a, b, kUlpsEpsilon);
}

/// Checks if [x] is absolutely smaller than y scaled by epsilon.
bool approximatelyZeroWhenComparedTo(double x, double y) {
  return x == 0 || x.abs() < (y * kFltEpsilon).abs();
}

/// Checks if x is negative within 4 [kDblEpsilon].
bool preciselyNegative(double x) {
  return x < kDblEpsilonErr;
}

/// Checks if b is in between a and c within 4 [kDblEpsilon].
bool preciselyBetween(double a, double b, double c) {
  return a <= c ? preciselyNegative(a - b) && preciselyNegative(b - c)
      : preciselyNegative(b - a) && preciselyNegative(c - b);
}

bool almostBetweenUlps(double a, double b, double c) {
  const int kUlpsEpsilon = 2;
  return a <= c ? lessOrEqualUlps(a, b, kUlpsEpsilon)
      && lessOrEqualUlps(b, c, kUlpsEpsilon)
      : lessOrEqualUlps(b, a, kUlpsEpsilon)
      && lessOrEqualUlps(c, b, kUlpsEpsilon);
}

/// Calculates a value to scale coefficients of a quadratic equation
/// with, to calculate roots without overflowing.
///
/// Returns a positive power of 2 that, when multiplied by n, and excepting
/// the two edge cases listed below, shifts the exponent of n to yield a
/// magnitude somewhere inside [1..2).
///
/// 1- Returns 2^1023 if abs(n) < 2^-1022 (including 0).
/// 2- Returns NaN if n is Inf or NaN.
///
/// Convert double to 64 bits, set exponent to -exponent but keep value.
///
/// See Press, W. H., Flannery, B. P., Teukolsky, S. A.,
///     & Vetterling, W. T. 1992, Numerical Recipes
///     (2d ed.; Cambridge: Cambridge Univ. Press)
double previousInversePow2(double n) {
  _DoubleBitConverter doubleBits = _DoubleBitConverter();
  doubleBits.value = n;
  int highBits = (0x7FEFFFFF - doubleBits.highBits) & 0x7FF00000;
  doubleBits.highBits = highBits;
  doubleBits.lowBits = 0;
  return doubleBits.value;
}

/// Calculates cube root using Halley's method.
double cubeRoot(double x) {
  if (approximatelyZeroCubed(x)) {
    return 0;
  }
  double result = _halleyCbrt3d(x.abs());
  // Preserve sign.
  if (x < 0) result = -result;
  return result;
}

// Cube root approximation using Kahan's cbrt.
double _cbrt5d(double d) {
  int b1 = 0x2a9f7893;
  final ByteData buffer = ByteData(16);
  buffer.setFloat64(0, 0.0);
  buffer.setFloat64(8, d);
  int dAsBitsLow = buffer.getUint32(8);
  int dAsBitsLowDiv3 = dAsBitsLow.toUnsigned(32) ~/ 3;
  // Won't overflow since we divided by 3 and b1 has zero first 2 bits.
  buffer.setUint32(0, dAsBitsLowDiv3 + b1);
  return buffer.getFloat64(0);
}

// iterative cube root approximation using Halley's method (double).
double _cbrtaHalleyd(double a, double R) {
  double a3 = a * a * a;
  double b = a * (a3 + R + R) / (a3 + a3 + R);
  return b;
}

// Cube root approximation using 3 iterations of Halley's method (double).
double _halleyCbrt3d(double d) {
  double a = _cbrt5d(d);
  a = _cbrtaHalleyd(a, d);
  a = _cbrtaHalleyd(a, d);
  return _cbrtaHalleyd(a, d);
}

bool preciselyLessThanZero(double x) {
  return x < kDblEpsilonErr;
}

bool preciselyGreaterThanOne(double x) {
  return x > 1 - kDblEpsilonErr;
}

bool approximatelyOneOrLessDouble(double x) => x < 1 + kFltEpsilonDouble;

bool approximatelyZeroOrMoreDouble(double x) => x > -kFltEpsilonDouble;

// Pin T value between 0 and 1.
double pinT(double t) {
  return preciselyLessThanZero(t) ? 0 : preciselyGreaterThanOne(t) ? 1 : t;
}

bool roughlyEqualPoints(double fX, double fY, double aX, double aY) {
  if (roughlyEqual(fX, aX) && roughlyEqual(fY, aY)) {
    return true;
  }
  double dist = math.sqrt(distanceSquared(fX, fY, aX, aY));
  double tiniest = math.min(math.min(math.min(fX, aX), fY), aY);
  double largest = math.max(math.max(math.max(fX, aX), fY), aY);
  largest = math.max(largest, -tiniest);
  return roughlyEqualUlps(largest, largest + dist);
}

bool approximatelyEqualPoints(double aX, double aY, double bX, double bY) {
  if (approximatelyEqualT(aX, bX) && approximatelyEqualT(aY, bY)) {
    return true;
  }
  if (!roughlyEqualUlps(aX, bX) || !roughlyEqualUlps(aY, bY)) {
    return false;
  }
  double dist = math.sqrt(distanceSquared(aX, aY, bX, bY));
  double tiniest = math.min(math.min(math.min(bX, aX), bY), aY);
  double largest = math.max(math.max(math.max(bX, aX), bY), aY);
  largest = math.max(largest, -tiniest);
  return almostDequalUlps(largest, largest + dist);
}

/// Returns distance between 2 points squared.
double distanceSquared(double p0x, double p0y, double p1x, double p1y) {
  final double dx = p0x - p1x;
  final double dy = p0y - p1y;
  return dx * dx + dy * dy;
}

const double kFltEpsilon = 1.19209290E-07; // == 1 / (2 ^ 23)
const double kDblEpsilon = 2.22045e-16;
const double kFltEpsilonCubed = kFltEpsilon * kFltEpsilon * kFltEpsilon;
const double kFltEpsilonHalf = kFltEpsilon / 2;
const double kFltEpsilonDouble = kFltEpsilon * 2;
// Epsilon to use when ordering vectors.
const double kFltEpsilonOrderableErr = kFltEpsilon * 16;
const double kFltEpsilonSquared = kFltEpsilon * kFltEpsilon;
// Use a compile-time constant for FLT_EPSILON_SQRT to avoid initializers.
// A 17 digit constant guarantees exact results.
const double kFltEpsilonSqrt = 0.00034526697709225118; // sqrt(kFltEpsilon);
const double kFltEpsilonInverse = 1 / kFltEpsilon;
const double kDblEpsilonErr = kDblEpsilon * 4;
const double kDblEpsilonSubdivideErr = kDblEpsilon * 16;
const double kRoughEpsilon = kFltEpsilon * 64;
const double kMoreRoughEpsilon = kFltEpsilon * 256;
const double kWayRoughEpsilon = kFltEpsilon * 2048;
const double kBumpEpsilon = kFltEpsilon * 4096;

// Scalar max is based on 32 bit float since [PathRef] stores values in
// Float32List.
const double kScalarMax = 3.402823466e+38;
const double kFltMax = 3.402823466e+38;
const double kScalarMin = -kScalarMax;
/// Max 32bit signed integer.
const int kMaxS32 = 2147483647;
/// Min 32bit signed integer.
const int kMinS32 = -2147483647;
