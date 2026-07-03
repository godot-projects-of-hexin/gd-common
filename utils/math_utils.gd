class_name GxMath
extends Object
## Stateless math helpers (gd-common). All static; do not instantiate.


## Move current toward target by at most delta (no overshoot).
static func approach(current: float, target: float, delta: float) -> float:
	if current < target:
		return minf(current + delta, target)
	return maxf(current - delta, target)


## Remap value from one range to another, clamped to [out_min, out_max].
static func remap_clamped(value: float, in_min: float, in_max: float, out_min: float, out_max: float) -> float:
	var t := clampf(inverse_lerp(in_min, in_max, value), 0.0, 1.0)
	return lerpf(out_min, out_max, t)


## Returns true with the given probability (0..1).
static func chance(probability: float) -> bool:
	return randf() < probability


## Random element from a non-empty array, else null.
## Accepts both untyped `Array` and typed `Array[T]` (coerced via Variant).
static func pick_random(arr) -> Variant:
	if arr == null or arr.is_empty():
		return null
	return arr[randi() % arr.size()]
