extends GdUnitTestSuite


func test_camera_trauma_is_clamped_and_decays_deterministically() -> void:
	var camera := auto_free(Camera.new()) as Camera
	camera.noise.seed = 99
	camera.add_trauma(2.0)

	assert_float(camera.trauma).is_equal(1.0)
	camera._process(0.25)

	assert_float(camera.trauma).is_less(1.0)
	assert_float(camera.offset.length()).is_greater(0.0)
	camera._process(2.0)
	assert_float(camera.trauma).is_equal(0.0)
	assert_object(camera.offset).is_equal(Vector2.ZERO)
