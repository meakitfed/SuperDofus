## Security (roadmap S.05), an extension of Protocol: the error codes of the domain. No message:
## a server that refuses a client for sending too much answers `error{code: rate_limited}` and
## closes the connection (code 1008) when the client keeps going. Same rules as Protocol.
class_name ProtocolSecurity
extends RefCounted

const E_RATE_LIMITED := "rate_limited" # too many messages per second on this connection
const ERROR_CODES := [E_RATE_LIMITED]
