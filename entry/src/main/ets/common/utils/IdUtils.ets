export class IdUtils {
  static uuid(): string {
    const template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return template.replace(/[xy]/g, (char: string) => {
      const randomValue = Math.floor(Math.random() * 16)
      const value = char === 'x' ? randomValue : (randomValue & 0x3) | 0x8
      return value.toString(16)
    })
  }
}
