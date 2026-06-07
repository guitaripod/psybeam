export async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input))
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

export function utcDayStamp(now: Date = new Date()): string {
  return now.toISOString().slice(0, 10).replace(/-/g, '')
}

export function utcMinuteStamp(now: Date = new Date()): string {
  return now.toISOString().slice(0, 16).replace(/[-:T]/g, '')
}
