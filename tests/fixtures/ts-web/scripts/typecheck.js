const fs = require('fs')

const source = fs.readFileSync('src/greet.ts', 'utf8')
if (!source.includes('export interface Greeting') || source.includes(': any')) {
  process.exit(1)
}
