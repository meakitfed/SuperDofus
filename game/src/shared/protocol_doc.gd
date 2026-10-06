class_name ProtocolDoc
extends RefCounted

## Markdown reference generated from SCHEMA (docs/PROTOCOL.md).
static func describe() -> String:
	var lines := PackedStringArray([
		"# Protocole SuperDofus (version %d)" % Protocol.VERSION, "",
		"Généré depuis `game/src/shared/protocol.gd` (`SCHEMA`) par `tools/protocol_doc.gd` : ne pas éditer à la main.", "",
		"Chaque message est un objet JSON `{t, seq?, …}`. Les commandes sont numérotées par le client ; les événements sont numérotés par la sim, par session. Une erreur porte `ref`, le `seq` de la commande refusée. Les champs en plus sont tolérés, et un champ manquant ou mal typé fait rejeter la commande (`error{code: bad_message}`). Les nombres peuvent revenir en flottants après JSON : faire `int()` à la lecture.", ""])
	var all := Protocol.SCHEMA.merged(ProtocolParty.SCHEMA).merged(ProtocolWatch.SCHEMA).merged(ProtocolResume.SCHEMA).merged(ProtocolAdmin.SCHEMA).merged(ProtocolCluster.SCHEMA).merged(ProtocolTrade.SCHEMA).merged(ProtocolContacts.SCHEMA)
	for direction: String in [Protocol.C2S, Protocol.S2C]:
		lines.append("## " + direction.capitalize())
		lines.append("")
		lines.append("| Type | Champs | Sens |")
		lines.append("|---|---|---|")
		for type: String in all:
			var entry: Array = all[type]
			if entry[0] != direction:
				continue
			var fields := PackedStringArray()
			for f: String in entry[2]:
				fields.append("`%s`: %s" % [f, entry[2][f]])
			lines.append("| `%s` | %s | %s |" % [type, ", ".join(fields) if not fields.is_empty() else "—", entry[1]])
		lines.append("")
	lines.append("## Codes d'erreur")
	lines.append("")
	var codes := PackedStringArray()
	for c: String in Protocol.ERROR_CODES:
		codes.append("`%s`" % c)
	lines.append(", ".join(codes))
	lines.append("")
	lines.append("Le détail des dictionnaires imbriqués (acteur, combattant, buff, effet, récompense, personnage) est en tête de `protocol.gd`.")
	return "\n".join(lines) + "\n"
