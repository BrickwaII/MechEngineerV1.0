class_name FightService
extends RefCounted
## Runs a fight and reports how it went. Extend it and override start_fight().
## StubFightService is the stand-in until fight/ provides real fights.
##
## finished is never emitted from inside start_fight(): at the earliest it comes
## on the next frame, so a fight that runs as a scene fits the same shape.
## Keep a reference to the service until finished arrives.

signal finished(result: FightResult)


func start_fight(_request: FightRequest) -> void:
	push_error("%s does not override FightService.start_fight()" % get_script().resource_path)
