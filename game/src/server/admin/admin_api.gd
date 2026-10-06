## Admin routes of the HTTP port (roadmap A1.01b, A1.02):
##   GET  /admin, /admin/       the dashboard page (static, holds no secret: it asks for the token)
##   GET  /admin/metrics        ServerMetrics.snapshot as JSON
##   GET  /admin/overview       metrics + connected players + running fights + account count
##   GET  /admin/accounts?q=    search (login or character name)
##   GET  /admin/account?login= sheet of an account
##   GET  /admin/character?world=&name=   sheet of a character (live when connected)
##   GET  /admin/worlds         the worlds, open or startable (WorldCluster.list)
##   GET  /admin/audit?limit=   newest audit entries first
##   POST /admin/action         JSON body {action, ...} (see AdminActions); every one is audited
## Needs `Authorization: Bearer <admin token>`, a secret of the server owner (--admin-token or
## the SUPERDOFUS_ADMIN_TOKEN environment variable), distinct from the session tokens of the
## players: a session token never opens these routes. No admin token configured = the routes do
## not exist (404). Nothing here knows which game a world runs.
class_name AdminApi
extends RefCounted

const PAGE := "res://src/server/admin/web/index.html"

var token := ""
var metrics := ServerMetrics.new()
var host: ServerHost
var views := AdminViews.new()
var actions := AdminActions.new()


func handles(path: String) -> bool:
	var p := path.get_slice("?", 0)
	return p == "/admin" or p.begins_with("/admin/")


func handle(req: HttpServer.Request) -> HttpServer.Response:
	if token == "":
		return HttpServer.Response.text(404, "not found")
	var route := req.path.get_slice("?", 0).trim_suffix("/")
	if route == "/admin" and req.method == "GET": # the page itself: public, the token is typed in it
		return _page()
	if not _authorized(req):
		var r := HttpServer.Response.text(401, "admin token required")
		r.headers["WWW-Authenticate"] = "Bearer"
		return r
	views.host = host
	actions.host = host
	if route == "/admin/action":
		if req.method != "POST":
			return HttpServer.Response.text(405, "POST only")
		var body: Variant = JSON.parse_string(req.body.get_string_from_utf8())
		if not body is Dictionary:
			return HttpServer.Response.text(400, "JSON object expected")
		return HttpServer.Response.json(200, actions.run(body))
	if req.method != "GET":
		return HttpServer.Response.text(405, "GET only")
	var q := query(req.path)
	match route:
		"/admin/metrics":
			return HttpServer.Response.json(200, metrics.snapshot(host))
		"/admin/overview":
			return HttpServer.Response.json(200, views.overview())
		"/admin/accounts":
			return HttpServer.Response.json(200, views.accounts(str(q.get("q", ""))))
		"/admin/account":
			return _found(views.account(str(q.get("login", ""))))
		"/admin/character":
			return _found(views.character(str(q.get("world", "")), str(q.get("name", ""))))
		"/admin/worlds":
			return HttpServer.Response.json(200, {"worlds": host.cluster.list(true)})
		"/admin/audit":
			return HttpServer.Response.json(200, views.audit(int(q.get("limit", 100))))
	return HttpServer.Response.text(404, "not found")


func _found(sheet: Dictionary) -> HttpServer.Response:
	if sheet.is_empty():
		return HttpServer.Response.text(404, "unknown")
	return HttpServer.Response.json(200, sheet)


func _page() -> HttpServer.Response:
	var f := FileAccess.open(PAGE, FileAccess.READ)
	if f == null:
		return HttpServer.Response.text(500, "dashboard page missing")
	var r := HttpServer.Response.new()
	r.headers["Content-Type"] = "text/html; charset=utf-8"
	r.headers["Cache-Control"] = "no-store"
	r.body = f.get_buffer(f.get_length())
	return r


## The query string of a request path as {name: value} (percent-decoded).
static func query(path: String) -> Dictionary:
	var out := {}
	if not path.contains("?"):
		return out
	for pair in path.get_slice("?", 1).split("&", false):
		var kv := pair.split("=", true, 1)
		out[kv[0].uri_decode()] = kv[1].replace("+", " ").uri_decode() if kv.size() == 2 else ""
	return out


func _authorized(req: HttpServer.Request) -> bool:
	var h := req.header("authorization")
	if not h.begins_with("Bearer "):
		return false
	return same(h.substr(7).strip_edges(), token)


## Comparison that does not stop at the first differing character.
static func same(a: String, b: String) -> bool:
	var x := a.to_utf8_buffer()
	var y := b.to_utf8_buffer()
	var diff := x.size() ^ y.size()
	for i in mini(x.size(), y.size()):
		diff |= x[i] ^ y[i]
	return diff == 0
