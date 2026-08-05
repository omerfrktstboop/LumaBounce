class_name ObstacleData
extends Resource

## 41+ bolumlerde kullanilan sabit ve hareketli engellerin paylasilan verisi.
## Gameplay, editor ve solver ayni Resource alanlarini okur.

enum Kind {
	METAL_RING,
	BOMB,
	ROTATING_WHEEL,
	MOVING_BAR,
	SPEED_BOOST,
}

const KIND_IDS := {
	Kind.METAL_RING: "metal_ring",
	Kind.BOMB: "bomb",
	Kind.ROTATING_WHEEL: "rotating_wheel",
	Kind.MOVING_BAR: "moving_bar",
	Kind.SPEED_BOOST: "speed_boost",
}

@export var kind: Kind = Kind.METAL_RING
@export var position := Vector2(360.0, 640.0)
@export var rotation_degrees := 0.0

## Halka: x dis cap. Bomba: x cap. Cark: x cap, y kol kalinligi.
## Kayan bariyer: gercek dikdortgen boyutu.
@export var size := Vector2(150.0, 28.0)
## Yalnizca halka icin deligin yaricapi.
@export var inner_radius := 42.0
## Yalnizca cark icin radyal kol sayisi.
@export_range(3, 8, 1) var spoke_count := 6
## Carkin saniyedeki donusu. Negatif deger ters yone doner.
@export var angular_speed_degrees := 55.0
## Kayan bariyerin dunya eksenindeki hareket yonu.
@export var motion_direction_degrees := 0.0
## Merkezden iki yone azami uzaklik.
@export var travel_distance := 110.0
## Bir tam gidis-donus suresi.
@export var motion_period := 2.8
## Ayni tur engellerin birlikte hareket etmemesi icin baslangic fazi.
@export var phase_degrees := 0.0


func kind_id() -> String:
	return String(KIND_IDS.get(kind, "metal_ring"))


func display_name() -> String:
	match kind:
		Kind.METAL_RING:
			return "Metal halka"
		Kind.BOMB:
			return "Bomba"
		Kind.ROTATING_WHEEL:
			return "Donen cark"
		Kind.MOVING_BAR:
			return "Kayan engel"
		Kind.SPEED_BOOST:
			return "Hızlandirici"
	return "Engel"


func outer_radius() -> float:
	return maxf(size.x * 0.5, 1.0)


func bomb_radius() -> float:
	return maxf(size.x * 0.5, 1.0)


func motion_position(seconds: float) -> Vector2:
	if kind != Kind.MOVING_BAR:
		return position
	var phase := deg_to_rad(phase_degrees) + TAU * seconds / maxf(motion_period, 0.1)
	var direction := Vector2.RIGHT.rotated(deg_to_rad(motion_direction_degrees))
	return position + direction * sin(phase) * travel_distance


func motion_rotation(seconds: float) -> float:
	var angle := rotation_degrees
	if kind == Kind.ROTATING_WHEEL:
		angle += angular_speed_degrees * seconds
	return deg_to_rad(angle)


static func from_kind_id(value: String) -> Kind:
	match value:
		"bomb":
			return Kind.BOMB
		"rotating_wheel":
			return Kind.ROTATING_WHEEL
		"moving_bar":
			return Kind.MOVING_BAR
		"speed_boost":
			return Kind.SPEED_BOOST
		_:
			return Kind.METAL_RING


func validate(index: int, play_rect := LevelData.DEFAULT_PLAY_RECT) -> PackedStringArray:
	var problems := PackedStringArray()
	var label := "engel %d" % index
	if not play_rect.has_point(position):
		problems.append("%s konumu oyun alani disinda %s" % [label, position])
	if not is_finite(rotation_degrees):
		problems.append("%s acisi sonlu olmali" % label)

	match kind:
		Kind.METAL_RING:
			var outer := outer_radius()
			if outer < 44.0 or outer > 150.0:
				problems.append("%s halka dis yaricapi 44-150 olmali (%.1f)" % [label, outer])
			if inner_radius < 28.0 or inner_radius > outer - 12.0:
				problems.append("%s halka deligi gecersiz (%.1f)" % [label, inner_radius])
		Kind.BOMB:
			if bomb_radius() < 24.0 or bomb_radius() > 70.0:
				problems.append("%s bomba yaricapi 24-70 olmali (%.1f)" % [label, bomb_radius()])
		Kind.ROTATING_WHEEL:
			if outer_radius() < 42.0 or outer_radius() > 130.0:
				problems.append("%s cark yaricapi 42-130 olmali" % label)
			if size.y < 14.0 or size.y > 40.0:
				problems.append("%s cark kol kalinligi 14-40 olmali" % label)
			if spoke_count < 3 or spoke_count > 8:
				problems.append("%s cark kol sayisi 3-8 olmali" % label)
			if absf(angular_speed_degrees) < 10.0 or absf(angular_speed_degrees) > 180.0:
				problems.append("%s cark hizi 10-180 derece/sn olmali" % label)
		Kind.MOVING_BAR:
			if size.x < 80.0 or size.x > 380.0 or size.y < 20.0 or size.y > 72.0:
				problems.append("%s kayan bariyer boyutu gecersiz %s" % [label, size])
			if travel_distance < 20.0 or travel_distance > 260.0:
				problems.append("%s hareket mesafesi 20-260 olmali" % label)
			if motion_period < 1.0 or motion_period > 8.0:
				problems.append("%s hareket suresi 1-8 sn olmali" % label)
		Kind.SPEED_BOOST:
			var outer := outer_radius()
			if outer < 15.0 or outer > 120.0:
				problems.append("%s hizlandirici yaricapi 15-120 olmali (%.1f)" % [label, outer])
	return problems
