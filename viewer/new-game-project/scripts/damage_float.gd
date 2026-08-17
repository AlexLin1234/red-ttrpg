class_name DamageFloat
extends Label3D


func show_amount(amount: int, healing := false) -> void:
	text = ("+%d" if healing else "-%d") % amount
	modulate = Color("68ff9b") if healing else Color("ff3f67")
	outline_modulate = Color(0.01, 0.01, 0.02, 1)
	var tween := create_tween().set_parallel(true)
	(
		tween
		. tween_property(self, "position:y", position.y + 2.2, 1.15)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	tween.tween_property(self, "modulate:a", 0.0, 1.15).set_delay(0.35)
	tween.chain().tween_callback(queue_free)
