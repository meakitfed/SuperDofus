## Password hashing for the accounts of a server (roadmap S.02a). Nothing here
## knows which game a world runs.
##
## APPROX(S.02a): Godot has neither argon2 nor bcrypt without a GDExtension, so the
## hash is an iterated SHA-256 with a random 16-byte salt: h0 = sha256(salt + password),
## h(i+1) = sha256(h(i) + salt + password), ITERATIONS times (the password is mixed in at
## every round, like PBKDF2 mixes it in every HMAC). 100 000 rounds cost about 0.1 s on
## the server. The count is stored with each hash, so it can be raised later without
## locking anyone out. To be replaced in S.05 if a GDExtension is available.
class_name PasswordHash
extends RefCounted

const ITERATIONS := 100000
const SALT_BYTES := 16


## {salt, hash, iterations}: hex strings and a count, JSON-safe.
static func make(password: String, iterations := ITERATIONS) -> Dictionary:
	var salt := Crypto.new().generate_random_bytes(SALT_BYTES).hex_encode()
	return {"salt": salt, "hash": digest(password, salt, iterations), "iterations": iterations}


static func digest(password: String, salt: String, iterations: int) -> String:
	var h := (salt + password).sha256_text()
	for i in maxi(1, iterations) - 1:
		h = (h + salt + password).sha256_text()
	return h


static func verify(password: String, record: Dictionary) -> bool:
	if not record.has("hash") or not record.has("salt"):
		return false
	return same(digest(password, str(record["salt"]), int(record.get("iterations", ITERATIONS))), str(record["hash"]))


## Constant-time comparison: the time does not depend on where the strings differ.
static func same(a: String, b: String) -> bool:
	var diff := a.length() ^ b.length()
	for i in mini(a.length(), b.length()):
		diff |= a.unicode_at(i) ^ b.unicode_at(i)
	return diff == 0
