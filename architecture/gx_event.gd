class_name GxEvent
extends RefCounted
## Base class for architecture events.
##
## An event is a *fact that already happened*, so name it in the past tense
## and keep it immutable in practice: fill its fields at construction and do
## not mutate them in handlers. Declare the payload as real fields so the
## contract is visible in code.
## [codeblock]
## class_name ScoreChangedEvent
## extends GxEvent
##
## var score: int
##
## static func create(value: int) -> ScoreChangedEvent:
##     var event := ScoreChangedEvent.new()
##     event.score = value
##     return event
## [/codeblock]
