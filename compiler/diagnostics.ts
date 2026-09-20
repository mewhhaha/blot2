export interface Diagnostic {
  readonly code: string;
  readonly subject: string;
  readonly message: string;
}

export class CompilerError extends Error {
  readonly code: string;
  readonly subject: string;
  readonly detail: string;

  constructor(diagnostic: Diagnostic) {
    super(`${diagnostic.subject}: ${diagnostic.message}`);
    this.name = "CompilerError";
    this.code = diagnostic.code;
    this.subject = diagnostic.subject;
    this.detail = diagnostic.message;
  }
}
