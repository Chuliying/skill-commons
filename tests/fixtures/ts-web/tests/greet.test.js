const fs = require('fs')

const source = fs.readFileSync('src/greet.ts', 'utf8')
if (!source.includes('hello ${name}')) process.exit(1)
