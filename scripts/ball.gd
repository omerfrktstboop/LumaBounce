class_name Ball
extends CharacterBody2D

## Firlatilabilir top. Sahnedeki en parlak eleman: neon camgobegi bir kure.
##
## Hareket tamamen kinematiktir: her fizik adiminda yer cekimi uygulanir,
## move_and_collide ile hareket edilir ve carpismada hiz carpisma normaline
## gore yansitilir (velocity.bounce(normal) == velocity - 2 * v.dot(n) * n).
## Rastgelelik yoktur, fizik adimi sabittir -> ayni atis ayni sonucu verir.

## Topun bir yuzeye carptigi an (konum, yuzey normali, carpma hizi).
signal bounced(bounce_position: Vector2, normal: Vector2, impact_speed: float)
## Atis basarisiz bitti: "out_of_bounds" veya "settled".
signal shot_failed(reason: String)

enum State {
	READY,   ## Firlaticida bekliyor.
	FLYING,  ## Havada.
	STOPPED, ## Durduruldu (hedef vuruldu veya atis iptal edildi).
}

@export_group("Fizik")
@export var radius := 24.0
@export var gravity := 1500.0
## Carpisma sonrasi korunan hiz orani. 1.0'a yakin = enerjisini kaybetmez.
@export_range(0.5, 1.0, 0.01) var bounciness := 0.94
## Carpisma sonrasi normal yonundeki en dusuk ayrilma hizi (yuzeye yapismayi onler).
@export var min_separation_speed := 60.0
@export var max_speed := 3000.0
## Tek fizik adiminda cozulecek en fazla carpisma sayisi.
@export var max_bounces_per_step := 6
## Bu hizin altindaki carpismalar icin efekt/sinyal uretilmez.
@export var min_impact_for_feedback := 150.0

@export_group("Takilma ve Sinirlar")
## Bu hizin altinda kalirsa top "olmus" sayilir.
@export var settle_speed := 80.0
## Kac saniye kesintisiz dusuk hizda kalinca atis iptal edilir.
@export var settle_time := 0.85
## Oyun alaninin bu kadar disina cikinca atis sifirlanir.
@export var out_of_bounds_margin := 240.0

@export_group("Gorunum")
@export var accent := Palette.ACCENT
@export var core_color := Palette.ACCENT_CORE
## Dis halenin yaricap carpani.
@export var glow_scale := 2.2
@export var squash_amount := 0.16
@export var squash_time := 0.15

@export_group("Iz")
@export var trail_length := 16
@export var trail_alpha := 0.42
@export var trail_fade_time := 0.28
## Iki iz noktasi arasindaki en kucuk mesafe.
@export var trail_min_step := 6.0

## Oyun alani; gameplay.gd tarafindan atanir. Bos birakilirsa viewport kullanilir.
var play_bounds := Rect2()

var state: State = State.READY

@onready var _shape: CollisionShape2D = $Shape
@onready var _visual: Node2D = $Visual
@onready var _trail: Line2D = $Trail

var _shell: Node2D
var _settle_timer := 0.0
var _squash_tween: Tween
var _trail_tween: Tween


func _ready() -> void:
	_apply_shape()
	_build_visual()
	_setup_trail()
	set_physics_process(false)


# --- Dis API -----------------------------------------------------------------

func reset_to(spawn_position: Vector2) -> void:
	set_physics_process(false)
	state = State.READY
	velocity = Vector2.ZERO
	global_position = spawn_position
	_settle_timer = 0.0
	_stop_squash()
	_clear_trail()
	show()


func launch(impulse: Vector2) -> void:
	if state != State.READY:
		return
	velocity = impulse.limit_length(max_speed)
	state = State.FLYING
	_settle_timer = 0.0
	_clear_trail()
	set_physics_process(true)


func stop() -> void:
	velocity = Vector2.ZERO
	state = State.STOPPED
	set_physics_process(false)
	_fade_trail()


func is_ready_to_launch() -> bool:
	return state == State.READY


func is_flying() -> bool:
	return state == State.FLYING


# --- Fizik -------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if state != State.FLYING:
		return
	velocity.y += gravity * delta
	velocity = velocity.limit_length(max_speed)
	_move_and_bounce(delta)
	_push_trail_point()
	if state != State.FLYING:
		return
	_update_settle_watchdog(delta)
	_check_out_of_bounds()


## Kalan hareketi carpismalar boyunca yansitarak tuketir.
func _move_and_bounce(delta: float) -> void:
	var motion := velocity * delta
	for _step in max_bounces_per_step:
		var collision := move_and_collide(motion)
		if collision == null:
			return
		var normal := collision.get_normal()
		var impact_speed := velocity.length()

		# Asil sekme: hizi carpisma normaline gore yansit.
		velocity = velocity.bounce(normal) * bounciness
		_enforce_separation(normal)
		motion = collision.get_remainder().bounce(normal) * bounciness

		if impact_speed >= min_impact_for_feedback:
			bounced.emit(collision.get_position(), normal, impact_speed)
			_play_squash(normal)


## Yuzeyden yeterince ayrilmayi garanti eder; titreyip yapismayi onler.
func _enforce_separation(normal: Vector2) -> void:
	if velocity.is_zero_approx():
		velocity = normal * min_separation_speed
		return
	var along_normal := velocity.dot(normal)
	if along_normal < min_separation_speed:
		velocity += normal * (min_separation_speed - along_normal)


## Top uzun sure cok yavas kalirsa atisi bitir.
func _update_settle_watchdog(delta: float) -> void:
	if velocity.length() >= settle_speed:
		_settle_timer = 0.0
		return
	_settle_timer += delta
	if _settle_timer >= settle_time:
		_fail("settled")


func _check_out_of_bounds() -> void:
	var bounds := play_bounds if play_bounds.has_area() else get_viewport_rect()
	if not bounds.grow(out_of_bounds_margin).has_point(global_position):
		_fail("out_of_bounds")


func _fail(reason: String) -> void:
	if state != State.FLYING:
		return
	stop()
	shot_failed.emit(reason)


# --- Gorunum -----------------------------------------------------------------

func _apply_shape() -> void:
	# Sahne icindeki alt kaynak paylasilmasin diye her ornek kendi sekliyle calisir.
	var circle := CircleShape2D.new()
	circle.radius = radius
	_shape.shape = circle


## Icten aydinlanmis neon kure: disa dogru yumusayan hale + parlak cekirdek.
func _build_visual() -> void:
	for child in _visual.get_children():
		child.queue_free()

	_shell = Node2D.new()
	_shell.name = "Shell"
	_visual.add_child(_shell)

	# Kontrollu hale katmanlari (disaridan iceriye).
	var halos := [
		{"scale": glow_scale, "alpha": 0.05},
		{"scale": glow_scale * 0.72, "alpha": 0.09},
		{"scale": glow_scale * 0.53, "alpha": 0.16},
	]
	for halo in halos:
		var halo_scale: float = halo["scale"]
		var halo_alpha: float = halo["alpha"]
		_shell.add_child(ShapeBuilder.make_polygon(
			ShapeBuilder.circle(radius * halo_scale, 40), Color(accent, halo_alpha)))

	# Govde ve icten parlayan cekirdek.
	_shell.add_child(ShapeBuilder.make_polygon(
		ShapeBuilder.circle(radius, 40), accent))
	_shell.add_child(ShapeBuilder.make_polygon(
		ShapeBuilder.circle(radius * 0.52, 28), Color(core_color, 0.92)))


func _setup_trail() -> void:
	# top_level: iz noktalari dunya uzayinda tutulur, top hareket edince kaymaz.
	# Ancak top_level, canvas item'i ebeveynden kopardigi icin z sirasi da
	# gorelilikten cikar; bu yuzden mutlak z veriyoruz (topun bir altinda).
	_trail.top_level = true
	_trail.z_as_relative = false
	_trail.z_index = z_index - 1
	_trail.width = radius * 1.0
	_trail.joint_mode = Line2D.LINE_JOINT_ROUND
	_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.antialiased = true

	var width_curve := Curve.new()
	width_curve.add_point(Vector2(0.0, 0.05))
	width_curve.add_point(Vector2(1.0, 1.0))
	_trail.width_curve = width_curve

	var gradient := Gradient.new()
	gradient.set_color(0, Color(accent, 0.0))
	gradient.set_color(1, Color(accent, trail_alpha))
	_trail.gradient = gradient


func _push_trail_point() -> void:
	var count := _trail.get_point_count()
	if count > 0 and _trail.get_point_position(count - 1).distance_to(global_position) < trail_min_step:
		return
	_trail.add_point(global_position)
	while _trail.get_point_count() > trail_length:
		_trail.remove_point(0)


func _clear_trail() -> void:
	if _trail_tween != null and _trail_tween.is_valid():
		_trail_tween.kill()
	_trail.modulate.a = 1.0
	_trail.clear_points()


func _fade_trail() -> void:
	if _trail.get_point_count() == 0:
		return
	if _trail_tween != null and _trail_tween.is_valid():
		_trail_tween.kill()
	_trail_tween = create_tween()
	_trail_tween.tween_property(_trail, "modulate:a", 0.0, trail_fade_time)


## Carpma yonune dik kisa bir ezilme animasyonu.
func _play_squash(normal: Vector2) -> void:
	_stop_squash()
	_shell.rotation = normal.angle() + PI * 0.5
	_shell.scale = Vector2(1.0 + squash_amount, 1.0 - squash_amount)
	_squash_tween = create_tween()
	_squash_tween.tween_property(_shell, "scale", Vector2.ONE, squash_time) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _stop_squash() -> void:
	if _squash_tween != null and _squash_tween.is_valid():
		_squash_tween.kill()
	if _shell != null:
		_shell.scale = Vector2.ONE
		_shell.rotation = 0.0
