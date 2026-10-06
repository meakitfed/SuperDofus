export const meta = {
  name: 'suite-chain-5',
  description: 'Enchaîne 5 lots précis SuperDofus (P2.02, P2.03, P1.15, P2.05, P2.08), un agent /suite à la fois',
  phases: [{ title: 'Lots', detail: 'un agent Sonnet 5.5 par lot, séquentiel, contexte neuf' }],
}
const LOTS = ['P2.03', 'P1.15', 'P2.05', 'P2.08']
const SCHEMA = {
  type: 'object',
  properties: {
    lot: { type: 'string' },
    status: { type: 'string', enum: ['done', 'partial', 'blocked'] },
    tests: { type: 'string' },
    summary: { type: 'string' },
  },
  required: ['lot', 'status', 'summary'],
}
const PROMPT = (i, lot, prev) => `Tu es l'agent ${i}/${LOTS.length} d'une chaîne qui avance la roadmap SuperDofus sans supervision humaine. Projet : C:\\Users\\natha\\Documents\\SuperDofus.
Exécute la commande /suite (outil Skill, skill "suite") avec l'argument « ${lot} » : c'est ton lot.
Contraintes supplémentaires :
- Si ${lot} est déjà EN COURS (laissé partiellement par un agent précédent), reprends-le là où il s'est arrêté (dernière ligne du Journal). S'il est trop gros pour une session, découpe-le (<ID>a, <ID>b…) et ne fais que le premier morceau. Si une dépendance n'est pas faite, fais d'abord le strict nécessaire de cette dépendance ou découpe le lot.
- Lots traités par cette chaîne : ${prev.length ? prev.join(', ') : 'aucun'}.
- Vérifie l'espace disque (df -h /c) avant toute extraction ; utilise --webp et n'extrais que le nécessaire.
- Le projet n'est pas un dépôt git : ni commit ni push.
- Les tests doivent finir verts, et le NOMBRE total de tests ne doit pas baisser (une erreur de parse dans un fichier de test est silencieuse : vérifie le total). Tu es le seul agent à travailler en ce moment.
- Fais tout le workflow /suite (code, tests, capture relue avec l'outil Read, doc, roadmap : statut, Journal, Découvertes, \`roadmap.py check\`, \`rules_sources.py --check\`). Les données serveur absentes du client (contenu des boutiques, positions, prix) se définissent dans le JSON du monde et se marquent APPROX(<lot>).
- Ne t'arrête pas pour poser une question : décide avec ton jugement et note les choix dans la roadmap.
Réponds avec le lot traité, son statut (done/partial/blocked), le résultat des tests (« N tests, M failures ») et un résumé d'une ligne.`

phase('Lots')
const results = []
const finished = []
for (let i = 0; i < LOTS.length; i++) {
  let r = null
  try {
    r = await agent(PROMPT(i + 1, LOTS[i], finished), { label: `${LOTS[i]} (${i + 1}/${LOTS.length})`, phase: 'Lots', model: 'sonnet', schema: SCHEMA })
  } catch (e) {
    log(`agent ${i + 1} a échoué : ${e}`)
  }
  if (!r) {
    log(`${LOTS[i]}: aucun résultat, on continue`)
    results.push({ i: i + 1, lot: LOTS[i], status: 'partial', summary: 'agent sans résultat' })
    continue
  }
  results.push({ i: i + 1, ...r })
  if (r.status === 'done') finished.push(LOTS[i])
  log(`${LOTS[i]} : ${r.status} — ${r.tests || ''} ${r.summary}`)
}
return results