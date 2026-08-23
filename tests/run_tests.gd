extends SceneTree

## Headless test runner.
##
##     godot --headless --script res://tests/run_tests.gd
##
## Exits non-zero when anything fails, so it works as a CI gate.

const Harness := preload("res://tests/harness.gd")

const SUITES := [
	preload("res://tests/test_resolver.gd"),
	preload("res://tests/test_events.gd"),
	preload("res://tests/test_tables.gd"),
	preload("res://tests/test_encounter.gd"),
	preload("res://tests/test_mortality.gd"),
	preload("res://tests/test_player_view.gd"),
	preload("res://tests/test_netrun.gd"),
	preload("res://tests/test_chase.gd"),
	preload("res://tests/test_downtime.gd"),
	preload("res://tests/test_encounter_tables.gd"),
	preload("res://tests/test_campaign.gd"),
	preload("res://tests/test_autosave.gd"),
	preload("res://tests/test_search.gd"),
	preload("res://tests/test_areas.gd"),
	preload("res://tests/test_map_rail.gd"),
	preload("res://tests/test_lifestyle.gd"),
	preload("res://tests/test_map_asset.gd"),
	preload("res://tests/test_character_rules.gd"),
	preload("res://tests/test_gear_market.gd"),
	preload("res://tests/test_economy.gd"),
	preload("res://tests/test_campaign_flow.gd"),
	preload("res://tests/test_rulebooks.gd"),
	preload("res://tests/test_item_database.gd"),
	preload("res://tests/test_model_database.gd"),
]


func _init() -> void:
	print("\nRedline test suite\n")
	var total_passed := 0
	var total_failed := 0

	for suite_script in SUITES:
		var harness: Harness = Harness.new()
		suite_script.run(harness)
		if not harness.report():
			total_failed += harness.failures.size()
		total_passed += harness.passed

	print("")
	if total_failed == 0:
		print("%d checks passed" % total_passed)
		quit(0)
	else:
		print("%d checks passed, %d FAILED" % [total_passed, total_failed])
		quit(1)
