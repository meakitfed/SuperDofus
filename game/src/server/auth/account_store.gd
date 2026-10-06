## The accounts of a server (roadmap S.02a), stored through Persistence in the
## `accounts` collection, key = login. The account document is shared with the
## account-wide data of the sim (bank…): the credentials live under "auth" and
## every other field is left alone.
##   accounts/<login> = {auth: {salt, hash, iterations, role, created}, bank: …}
## Never a password in a document, a message or a log: only its salted hash.
## Nothing here knows which game a world runs.
class_name AccountStore
extends RefCounted

const ROLE_PLAYER := "player"
const ROLE_GM := "gm"
const PASSWORD_MIN := 6
const PASSWORD_MAX := 128

static var _login_re := RegEx.create_from_string("^[a-z0-9_-]{3,24}$")

var persistence: Persistence
## the server may refuse to create accounts (the closed list of an admin)
var registration_open := true
## hash rounds for new accounts (tests lower it)
var iterations := PasswordHash.ITERATIONS
## the clock of the "created" field, injectable (Clock is the sim's, so unix seconds here)
var now_unix := Callable(Time, "get_unix_time_from_system")


func _init(p_persistence: Persistence) -> void:
	persistence = p_persistence


## Logins are case-insensitive: "Jean" and "jean" are one account.
static func normalize(login: String) -> String:
	return login.strip_edges().to_lower()


static func valid_login(login: String) -> bool:
	return _login_re.search(login) != null


func exists(login: String) -> bool:
	return not _auth(normalize(login)).is_empty()


## The checks of `register` that cost nothing (no hashing): "" if the account could be created.
func register_precheck(login: String, password: String) -> String:
	if not registration_open:
		return Protocol.E_REGISTRATION_CLOSED
	login = normalize(login)
	if not valid_login(login) or password.length() < PASSWORD_MIN or password.length() > PASSWORD_MAX:
		return Protocol.E_BAD_LOGIN
	if exists(login):
		return Protocol.E_LOGIN_TAKEN
	return ""


## "" if created, else a Protocol error code. `prepared` = PasswordHash.make(password) computed
## earlier (S.05c: the host hashes in a thread, then creates the account on the main thread).
func register(login: String, password: String, prepared := {}) -> String:
	var err := register_precheck(login, password)
	if err != "":
		return err
	login = normalize(login)
	var doc := persistence.load_account(login)
	var auth: Dictionary = prepared.duplicate() if not prepared.is_empty() else PasswordHash.make(password, iterations)
	auth["role"] = ROLE_PLAYER
	auth["created"] = int(now_unix.call())
	doc["auth"] = auth
	persistence.save_account(login, doc)
	return ""


## "" if the login and password match, else E_BAD_CREDENTIALS (the same answer for
## an unknown login and a wrong password; a hash is computed either way, so the
## time does not tell the two apart).
func check(login: String, password: String) -> String:
	return "" if AuthJob.verify(password, credentials(login), iterations) else Protocol.E_BAD_CREDENTIALS


## The stored credentials of a login ({} if unknown): what a thread needs to check a password
## without touching the store (S.05c, AuthJob).
func credentials(login: String) -> Dictionary:
	return _auth(normalize(login))


## ROLE_PLAYER when the account has no role.
func role(login: String) -> String:
	return str(_auth(normalize(login)).get("role", ROLE_PLAYER))


## Gives a role by hand (the admin lots do it through the GM console).
func set_role(login: String, role_name: String) -> bool:
	login = normalize(login)
	var doc := persistence.load_account(login)
	if not doc.has("auth"):
		return false
	doc["auth"]["role"] = role_name
	persistence.save_account(login, doc)
	return true


## New password for an existing account (admin web, A1.02): "" if changed, else a Protocol error
## code. The same length rules as register; nothing else of the document is touched.
func set_password(login: String, password: String) -> String:
	login = normalize(login)
	if not exists(login):
		return Protocol.E_UNKNOWN_CHARACTER
	if password.length() < PASSWORD_MIN or password.length() > PASSWORD_MAX:
		return Protocol.E_BAD_LOGIN
	var doc := persistence.load_account(login)
	var auth: Dictionary = doc["auth"]
	var fresh := PasswordHash.make(password, iterations)
	auth["salt"] = fresh["salt"]
	auth["hash"] = fresh["hash"]
	auth["iterations"] = fresh["iterations"]
	persistence.save_account(login, doc)
	return ""


## Last connection of an account: {at (unix ms), ip}, for the admin sheet (A1.02).
func note_seen(login: String, ip: String) -> void:
	login = normalize(login)
	if not exists(login):
		return
	var doc := persistence.load_account(login)
	doc["seen"] = {"at": int(float(now_unix.call()) * 1000.0), "ip": ip}
	persistence.save_account(login, doc)


## Logins of every account, sorted.
func logins() -> PackedStringArray:
	var out := PackedStringArray()
	for k in persistence.list_keys(Persistence.ACCOUNTS):
		if exists(k):
			out.append(k)
	return out


func _auth(login: String) -> Dictionary:
	if not valid_login(login): # a login comes from the network: never a path
		return {}
	var a: Variant = persistence.load_account(login).get("auth", {})
	return a if a is Dictionary else {}
