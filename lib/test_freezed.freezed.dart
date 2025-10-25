// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'test_freezed.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$TestFreezed {

 bool get isActive; int get count;
/// Create a copy of TestFreezed
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TestFreezedCopyWith<TestFreezed> get copyWith => _$TestFreezedCopyWithImpl<TestFreezed>(this as TestFreezed, _$identity);

  /// Serializes this TestFreezed to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TestFreezed&&(identical(other.isActive, isActive) || other.isActive == isActive)&&(identical(other.count, count) || other.count == count));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,isActive,count);

@override
String toString() {
  return 'TestFreezed(isActive: $isActive, count: $count)';
}


}

/// @nodoc
abstract mixin class $TestFreezedCopyWith<$Res>  {
  factory $TestFreezedCopyWith(TestFreezed value, $Res Function(TestFreezed) _then) = _$TestFreezedCopyWithImpl;
@useResult
$Res call({
 bool isActive, int count
});




}
/// @nodoc
class _$TestFreezedCopyWithImpl<$Res>
    implements $TestFreezedCopyWith<$Res> {
  _$TestFreezedCopyWithImpl(this._self, this._then);

  final TestFreezed _self;
  final $Res Function(TestFreezed) _then;

/// Create a copy of TestFreezed
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? isActive = null,Object? count = null,}) {
  return _then(_self.copyWith(
isActive: null == isActive ? _self.isActive : isActive // ignore: cast_nullable_to_non_nullable
as bool,count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [TestFreezed].
extension TestFreezedPatterns on TestFreezed {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TestFreezed value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TestFreezed() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TestFreezed value)  $default,){
final _that = this;
switch (_that) {
case _TestFreezed():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TestFreezed value)?  $default,){
final _that = this;
switch (_that) {
case _TestFreezed() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool isActive,  int count)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TestFreezed() when $default != null:
return $default(_that.isActive,_that.count);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool isActive,  int count)  $default,) {final _that = this;
switch (_that) {
case _TestFreezed():
return $default(_that.isActive,_that.count);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool isActive,  int count)?  $default,) {final _that = this;
switch (_that) {
case _TestFreezed() when $default != null:
return $default(_that.isActive,_that.count);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TestFreezed extends TestFreezed {
  const _TestFreezed({this.isActive = false, this.count = 0}): super._();
  factory _TestFreezed.fromJson(Map<String, dynamic> json) => _$TestFreezedFromJson(json);

@override@JsonKey() final  bool isActive;
@override@JsonKey() final  int count;

/// Create a copy of TestFreezed
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TestFreezedCopyWith<_TestFreezed> get copyWith => __$TestFreezedCopyWithImpl<_TestFreezed>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TestFreezedToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TestFreezed&&(identical(other.isActive, isActive) || other.isActive == isActive)&&(identical(other.count, count) || other.count == count));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,isActive,count);

@override
String toString() {
  return 'TestFreezed(isActive: $isActive, count: $count)';
}


}

/// @nodoc
abstract mixin class _$TestFreezedCopyWith<$Res> implements $TestFreezedCopyWith<$Res> {
  factory _$TestFreezedCopyWith(_TestFreezed value, $Res Function(_TestFreezed) _then) = __$TestFreezedCopyWithImpl;
@override @useResult
$Res call({
 bool isActive, int count
});




}
/// @nodoc
class __$TestFreezedCopyWithImpl<$Res>
    implements _$TestFreezedCopyWith<$Res> {
  __$TestFreezedCopyWithImpl(this._self, this._then);

  final _TestFreezed _self;
  final $Res Function(_TestFreezed) _then;

/// Create a copy of TestFreezed
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? isActive = null,Object? count = null,}) {
  return _then(_TestFreezed(
isActive: null == isActive ? _self.isActive : isActive // ignore: cast_nullable_to_non_nullable
as bool,count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
