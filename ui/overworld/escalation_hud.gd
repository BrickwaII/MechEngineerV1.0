extends Control
## Escalation over the map (R2-B): the alert meter in the map's top-left
## corner and news cards in its top-right. The overworld places it over the
## map and calls use() with each new Campaign.

const AlertMeter := preload("res://ui/overworld/alert_meter.gd")
const NewsCard := preload("res://ui/overworld/news_card.gd")

const MARGIN := 12.0

var campaign: Campaign
var meter: AlertMeter
var news: NewsCard


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter = AlertMeter.new()
	meter.name = "AlertMeter"
	meter.position = Vector2(MARGIN, MARGIN)
	add_child(meter)
	news = NewsCard.new()
	news.name = "NewsCard"
	add_child(news)
	news.resized.connect(_place_news)
	resized.connect(_place_news)


## Follows `c`: the meter shows its alert and its news cards queue. Cards of
## an earlier campaign are dropped.
func use(c: Campaign) -> void:
	if campaign != null:
		if campaign.changed.is_connected(meter.refresh):
			campaign.changed.disconnect(meter.refresh)
		if campaign.escalated.is_connected(news.push):
			campaign.escalated.disconnect(news.push)
	campaign = c
	news.clear()
	meter.escalation = c.escalation
	c.changed.connect(meter.refresh)
	c.escalated.connect(news.push)


func _place_news() -> void:
	news.position = Vector2(size.x - news.size.x - MARGIN, MARGIN)
