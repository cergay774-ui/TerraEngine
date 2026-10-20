// The Bedrock script runtime provides a console object (output goes to the
// content log). The official typings do not declare it.
declare const console: {
  log(...data: unknown[]): void;
  warn(...data: unknown[]): void;
  error(...data: unknown[]): void;
};
