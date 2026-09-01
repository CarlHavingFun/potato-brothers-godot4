extends GdUnitTestSuite


const ARENA_RECT := Rect2(Vector2.ZERO, Vector2(2048, 1536))
const OPENING_VIEW_RECT := Rect2(Vector2(384, 408), Vector2(1280, 720))
const HUD_EXCLUSION_RECTS: Array[Rect2] = [
	Rect2(384, 408, 368, 244),
	Rect2(832, 408, 384, 112),
]


func test_first_six_noninteractive_props_compose_inside_the_opening_camera() -> void:
	var presenter := auto_free(GogoStaticWorldPresenter.new()) as GogoStaticWorldPresenter
	presenter.set("_arena_rect", ARENA_RECT)
	var sockets: Array = presenter.call("_prop_sockets", 9137)
	assert_int(sockets.size()).is_greater_equal(6)
	var accepted: Array[Vector2] = []
	for index in 6:
		var point := sockets[index] as Vector2
		assert_bool(OPENING_VIEW_RECT.has_point(point)).is_true()
		assert_float(point.distance_to(ARENA_RECT.get_center())).is_greater_equal(240.0)
		for exclusion in HUD_EXCLUSION_RECTS:
			assert_bool(exclusion.grow(32.0).has_point(point)).is_false()
		for prior in accepted:
			assert_float(point.distance_to(prior)).is_greater_equal(128.0)
		accepted.append(point)
