## What the quest events change on screen (P2.03, split from client_session.gd).
class_name QuestEvents
extends RefCounted


static func apply(t: String, ev: Dictionary, hud: PlayerHud, toast: Toast) -> void:
	match t:
		Protocol.QUEST_LIST:
			hud.quests.set_list(ev)
		Protocol.QUEST_START:
			hud.quests.quest_started(ev["quest"])
			toast.show_text(QuestTexts.headline(QuestTexts.NEW_QUEST, "Nouvelle quête : $quest{0}", QuestTexts.quest_name(int(ev["quest"]["name_id"]))))
		Protocol.QUEST_UPDATE:
			hud.quests.quest_updated(ev["quest"])
			if ev.has("rewards"):
				toast.show_text(QuestTexts.rewards_line(ev["rewards"]), UiStyle.GOOD)
		Protocol.QUEST_COMPLETE:
			hud.quests.quest_done(int(ev["quest"]), int(ev["name_id"]))
			toast.show_text(QuestTexts.headline(QuestTexts.QUEST_DONE, "Quête terminée : $quest{0}", QuestTexts.quest_name(int(ev["name_id"]))), UiStyle.GOOD)
			toast.show_text(QuestTexts.rewards_line(ev["rewards"]), UiStyle.GOOD)
