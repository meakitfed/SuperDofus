## Who is connected to a server (roadmap S.02a): register / login over an
## AccountStore, session tokens, and the rule of one live connection per account.
## A token is 32 random bytes (hex), valid while its connection lives: the content
## API (C.02) asks for it. The host calls login / register for a connection `conn`
## (any object that identifies it) and release(conn) when that connection ends.
## Nothing here knows which game a world runs.
class_name AuthService
extends RefCounted

## wrong passwords tolerated per connection before it is cut (S.05 will add real rate limits)
const MAX_FAILURES := 5

var accounts: AccountStore
## accounts with the GM role besides those whose document says so (--gm=<login>)
var gm_logins := PackedStringArray()

## how long the token of a connection that dropped without a logout stays valid (S.02b).
## APPROX(S.02b): 10 minutes, a fight that lasts longer releases the character anyway
var park_ttl_ms := 10 * 60 * 1000

var _by_token := {} # token -> login
var _online := {}   # login -> token (live connections and parked sessions)
var _parked := {}   # login -> expiry (ms, the host's clock): the connection dropped, the token waits


class Result:
	var ok := false
	var code := ""
	var token := ""
	var login := ""
	var role := ""


func _init(p_accounts: AccountStore) -> void:
	accounts = p_accounts


## Accounts with a live connection (parked sessions are not online).
func online_count() -> int:
	return _online.size() - _parked.size()


func is_online(login: String) -> bool:
	var key := AccountStore.normalize(login)
	return _online.has(key) and not _parked.has(key)


## True while the connection of `login` has dropped and its token waits for a resume.
func is_parked(login_name: String) -> bool:
	return _parked.has(login_name)


## Creates the account, then logs it in.
func register(login: String, password: String, prepared := {}) -> Result:
	var err := accounts.register(login, password, prepared)
	if err != "":
		return _fail(err)
	return _open(AccountStore.normalize(login))


func login(login_name: String, password: String) -> Result:
	return login_checked(login_name, accounts.check(login_name, password) == "")


## login once the password was checked elsewhere (S.05c: AuthJob, in a thread): `ok` = it matched.
func login_checked(login_name: String, ok: bool) -> Result:
	if not ok:
		return _fail(Protocol.E_BAD_CREDENTIALS)
	var key := AccountStore.normalize(login_name)
	if Sanctions.is_banned(accounts.persistence, key): # A1.01: after the password, so nobody learns who is banned
		return _fail(ProtocolAdmin.E_BANNED)
	if _parked.has(key): # the password proves it is the owner: the parked session (and token) is theirs
		_parked.erase(key)
		return _result(key, str(_online[key]))
	if _online.has(key): # checked after the password: nobody learns who is online
		return _fail(Protocol.E_ALREADY_CONNECTED)
	return _open(key)


## The login a token belongs to, "" if the token is unknown or its connection ended.
func login_for_token(token: String) -> String:
	return str(_by_token.get(token, ""))


## The connection of `login` ended: the token dies and the account can log in again.
func release(login_name: String) -> void:
	var token := str(_online.get(login_name, ""))
	_online.erase(login_name)
	_parked.erase(login_name)
	_by_token.erase(token)


## The connection of `login` dropped without a logout (S.02b): the token stays valid for
## `park_ttl_ms` from `now_ms` (the host's clock), for `resume` or a login with the password.
func park(login_name: String, now_ms: int) -> void:
	if _online.has(login_name):
		_parked[login_name] = now_ms + park_ttl_ms


## A new connection claims the session of `token`: ok when it is parked; bad_token when it is
## unknown or expired; already_connected when a live connection still holds it (the host may
## evict that one if it has been idle, then call again).
func resume(token: String) -> Result:
	var key := login_for_token(token)
	if key == "":
		return _fail(ProtocolResume.E_BAD_TOKEN)
	if not _parked.has(key):
		return _fail(Protocol.E_ALREADY_CONNECTED)
	if Sanctions.is_banned(accounts.persistence, key): # banned while its session was parked
		return _fail(ProtocolAdmin.E_BANNED)
	_parked.erase(key)
	return _result(key, token)


## Parked sessions whose time is up: their tokens die; returns their logins.
func expire(now_ms: int) -> PackedStringArray:
	var out := PackedStringArray()
	for key: String in _parked.keys():
		if now_ms >= int(_parked[key]):
			out.append(key)
	for key in out:
		release(key)
	return out


func _open(key: String) -> Result:
	var r := _result(key, Crypto.new().generate_random_bytes(32).hex_encode())
	_online[key] = r.token
	_by_token[r.token] = key
	return r


func _result(key: String, token: String) -> Result:
	var r := Result.new()
	r.ok = true
	r.login = key
	r.role = AccountStore.ROLE_GM if gm_logins.has(key) else accounts.role(key)
	r.token = token
	return r


func _fail(code: String) -> Result:
	var r := Result.new()
	r.code = code
	return r
