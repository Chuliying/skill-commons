const fs = require('fs')

const source = fs.readFileSync('src/Greeting.tsx', 'utf8')
if (!source.includes('text-foreground')) process.exit(1)
