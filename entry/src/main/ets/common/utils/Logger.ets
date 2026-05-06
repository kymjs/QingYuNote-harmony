export class Logger {
  private static redact(message: string): string {
    return message
      .replace(/password=([^&\s]+)/gi, 'password=***')
      .replace(/authorization:\s*basic\s+[a-z0-9+/=]+/gi, 'authorization: basic ***')
  }

  static info(tag: string, message: string): void {
    console.info(`[${tag}] ${Logger.redact(message)}`)
  }

  static warn(tag: string, message: string): void {
    console.warn(`[${tag}] ${Logger.redact(message)}`)
  }

  static error(tag: string, message: string): void {
    console.error(`[${tag}] ${Logger.redact(message)}`)
  }
}
