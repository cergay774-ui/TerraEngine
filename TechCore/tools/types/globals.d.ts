// Глобальные объекты среды Script API Bedrock, отсутствующие в lib ES2022.
declare const console: {
  log(...args: unknown[]): void;
  info(...args: unknown[]): void;
  warn(...args: unknown[]): void;
  error(...args: unknown[]): void;
};
