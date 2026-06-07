export function parseOutputLangs(csv: string | undefined): string[] {
  return (csv ?? '')
    .split(',')
    .map((s) => s.trim().toLowerCase())
    .filter((s) => s.length > 0)
}
