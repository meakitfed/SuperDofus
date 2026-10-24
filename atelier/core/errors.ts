/** An error the API turns into an HTTP status and a message the user can read. */
export class AtelierError extends Error {
  constructor(public status: number, message: string) { super(message); }
}
