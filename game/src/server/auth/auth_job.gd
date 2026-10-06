## One password hashing, made off the main thread (roadmap S.05c). 100 000 SHA-256 rounds take
## ~0.1 s: done in `ServerHost.poll` they would stall the tick of every world. The host builds a
## job on the main thread (the stored credentials are read there), runs `run` with
## WorkerThreadPool, and uses `ok` / `prepared` back on the main thread once the task is done.
## `run` touches nothing but the job's own fields: no store, no Persistence, no Node.
## Nothing here knows which game a world runs.
class_name AuthJob
extends RefCounted

var type := ""        # Protocol.LOGIN or Protocol.REGISTER
var login := ""
var password := ""
var record := {}      # LOGIN: the stored credentials ({} = unknown login)
var iterations := PasswordHash.ITERATIONS
var ok := false       # LOGIN: the password matches
var prepared := {}    # REGISTER: PasswordHash.make(password)
var task_id := -1


## Starts the job on a worker thread.
func start() -> void:
	task_id = WorkerThreadPool.add_task(run)


func is_done() -> bool:
	return task_id < 0 or WorkerThreadPool.is_task_completed(task_id)


## Waits for the task (it is cheap once done) and frees it; call it before dropping the job.
func finish() -> void:
	if task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(task_id)
		task_id = -1


func run() -> void:
	if type == Protocol.REGISTER:
		prepared = PasswordHash.make(password, iterations)
	else:
		ok = verify(password, record, iterations)
	if type != Protocol.REGISTER:
		password = "" # the clear text is not kept longer than needed (a register keeps it for the length check)


## True if `password` matches the stored `record`. An unknown login ({}) still computes a hash,
## so the time does not tell it from a wrong password.
static func verify(password: String, record: Dictionary, iterations: int) -> bool:
	if record.is_empty():
		PasswordHash.digest(password, "0".repeat(32), iterations)
		return false
	return PasswordHash.verify(password, record)
