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
	PULSE_LASER,
	# Yeni turler HER ZAMAN sona eklenir: .tres dosyalari turu tamsayi olarak
	# saklar, araya eklenen bir tur mevcut bolumlerin engellerini degistirirdi.
	PORTAL,
}

const KIND_IDS := {
	Kind.METAL_RING: "metal_ring",
	Kind.BOMB: "bomb",
	Kind.ROTATING_WHEEL: "rotating_wheel",
	Kind.MOVING_BAR: "moving_bar",
	Kind.SPEED_BOOST: "speed_boost",
	Kind.PULSE_LASER: "pulse_laser",
	Kind.PORTAL: "portal",
}

## PORTAL: topun merkezi halkanin bu oranindaki daireye girince isinlanir.
## Halkanin gorunen kenarina degmek yetmez; top gozle gorulur sekilde iceri
## "dalmali", yoksa kenardan siyiran bir atisin isinlanmasi haksiz gorunur.
const PORTAL_TRIGGER_RATIO := 0.75
## Bir atista en fazla bu kadar isinlanma. Cikis girisin ustundeyse top
## dusup tekrar girer ve sonsuz donguye girerdi; sinirdan sonra portal o atis
## icin soner (bkz. LevelObstacle) ve top normal ucusuna devam eder.
const PORTAL_MAX_TELEPORTS_PER_SHOT := 4

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
## Lazerde de ayni ise yarar: iki lazer sirayla yansin diye biri 180 alir.
@export var phase_degrees := 0.0
## LAZER: bir dongunun ne kadarinda ISIN ACIK olur (0..1).
##
## Dongu suresi motion_period'dir - kayan bariyerdeki "bir tam tur" ile ayni
## kavram oldugu icin ayri bir alan acilmadi. Varsayilan 3 sn dongude 0.667
## => 2 sn acik, 1 sn kapali.
##
## Ust sinir 0.85: surekli acik bir lazer zamanlama bulmacasi degil, gecilmez
## bir duvardir - o zaten kayan bariyerin isi.
@export_range(0.15, 0.85, 0.01) var pulse_on_ratio := 0.667
## PORTAL: tek bir ObstacleData bir CIFTI temsil eder - position giris,
## exit_position cikis. Boylece esi olmayan bir portal veri olarak var olamaz.
## Halka capi size.x'tir (giris ve cikis ayni boyuttadir).
@export var exit_position := Vector2(360.0, 400.0)
## PORTAL: cikista hiz vektoru bu kadar doner (0, 90, -90, 180). 0 = top
## girdigi yonde devam eder; okunabilirlik icin yalnizca dik acilar gecerlidir.
@export var exit_turn_degrees := 0.0


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
		Kind.PULSE_LASER:
			return "Lazer bariyer"
		Kind.PORTAL:
			return "Portal"
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


## PORTAL: isinlanmayi tetikleyen dairenin yaricapi (bkz. PORTAL_TRIGGER_RATIO).
func portal_trigger_radius() -> float:
	return outer_radius() * PORTAL_TRIGGER_RATIO


## PORTAL: cikistaki hiz. Buyukluk korunur; yalnizca yon exit_turn_degrees
## kadar doner.
func portal_exit_velocity(velocity: Vector2) -> Vector2:
	return velocity.rotated(deg_to_rad(exit_turn_degrees))


## PORTAL: [from, to] hareket parcasinin ILK girdigi giris portali.
## Donus: {"index": portals icindeki sira, "fraction": 0..1 parca orani}; yoksa {}.
##
## Ball (oyun) ve LevelSolver (cevrimdisi dogrulama) isinlanmayi YALNIZCA bu
## fonksiyonla bulur. Kural iki yerde ayri yazilsaydi zamanla ayrisir ve
## "editorde geciyor, oyunda gecmiyor" hatasi dogardi.
##
## Kare sonundaki konuma degil PARCAYA bakilir: top bir karede 50 px'e kadar
## ilerler, sadece uc nokta denetlense halkanin kenarindan gecen hizli bir
## atis portali atlayabilirdi.
static func first_portal_entry(portals: Array[ObstacleData], from: Vector2,
		to: Vector2) -> Dictionary:
	var best := {}
	var best_fraction := 2.0
	for i in portals.size():
		var data := portals[i]
		if data == null or data.kind != Kind.PORTAL:
			continue
		var fraction := _segment_enters_circle(
			from, to, data.position, data.portal_trigger_radius())
		if fraction >= 0.0 and fraction < best_fraction:
			best_fraction = fraction
			best = {"index": i, "fraction": fraction}
	return best


## Parca daireye girerse giris orani (0..1), zaten icinden baslarsa 0, aksi
## halde -1.
static func _segment_enters_circle(from: Vector2, to: Vector2, center: Vector2,
		radius: float) -> float:
	var relative := from - center
	var c := relative.length_squared() - radius * radius
	if c <= 0.0:
		return 0.0
	var motion := to - from
	var a := motion.length_squared()
	if a <= 0.000001:
		return -1.0
	var b := 2.0 * relative.dot(motion)
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return -1.0
	var fraction := (-b - sqrt(discriminant)) / (2.0 * a)
	if fraction < 0.0 or fraction > 1.0:
		return -1.0
	return fraction


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
		"pulse_laser":
			return Kind.PULSE_LASER
		"portal":
			return Kind.PORTAL
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
		Kind.PULSE_LASER:
			if size.x < 90.0 or size.x > 460.0:
				problems.append("%s lazer uzunlugu 90-460 olmali (%.1f)" % [label, size.x])
			if size.y < 8.0 or size.y > 30.0:
				problems.append("%s lazer isin kalinligi 8-30 olmali (%.1f)" % [label, size.y])
			if motion_period < 1.2 or motion_period > 6.0:
				problems.append("%s lazer dongusu 1.2-6 sn olmali (%.1f)" % [label, motion_period])
			if pulse_on_ratio < 0.15 or pulse_on_ratio > 0.85:
				problems.append("%s lazer acik orani 0.15-0.85 olmali (%.2f)" % [label, pulse_on_ratio])
		Kind.PORTAL:
			# Alt sinir: tetik dairesi (yaricapin %75'i) topun yaricapindan
			# (24) kucuk kalmasin, yoksa portala "dalmak" piksel avina doner.
			if outer_radius() < 36.0 or outer_radius() > 64.0:
				problems.append("%s portal yaricapi 36-64 olmali (%.1f)" % [label, outer_radius()])
			if not play_rect.has_point(exit_position):
				problems.append("%s portal cikisi oyun alani disinda %s" % [label, exit_position])
			# Giris ile cikis birbirine cok yakinsa isinlanma okunmaz, top
			# sadece biraz kaymis gibi gorunur.
			if position.distance_to(exit_position) < 220.0:
				problems.append("%s portal giris-cikis arasi en az 220 olmali (%.1f)"
					% [label, position.distance_to(exit_position)])
			if not int(round(exit_turn_degrees)) in [0, 90, -90, 180, -180] \
					or not is_equal_approx(exit_turn_degrees, round(exit_turn_degrees)):
				problems.append("%s portal donusu 0/90/-90/180 olmali (%.1f)"
					% [label, exit_turn_degrees])
	return problems


## LAZER: verilen anda isin ACIK mi?
##
## Zaman bolumdeki kesintisiz engel zaman cizelgesinden olculur. Runtime
## ipucu solver'i mevcut fazi offset olarak alir; offline solver 0 fazindan
## baslar (bkz. ObstacleField.get_motion_time ve LevelSolver.bind_space).
func laser_is_active(seconds: float) -> bool:
	if kind != Kind.PULSE_LASER:
		return false
	var period := maxf(motion_period, 0.1)
	var phase := phase_degrees / 360.0 + seconds / period
	return fposmod(phase, 1.0) < pulse_on_ratio


## Isinin bir sonraki durum degisimine kalan sure - gorsel uyari icin
## (bkz. LevelObstacle). Oyuncu isinin ne zaman yanacagini GOREBILMELI,
## yoksa bulmaca zamanlama degil sans olur.
func laser_phase_ratio(seconds: float) -> float:
	var period := maxf(motion_period, 0.1)
	return fposmod(phase_degrees / 360.0 + seconds / period, 1.0)
