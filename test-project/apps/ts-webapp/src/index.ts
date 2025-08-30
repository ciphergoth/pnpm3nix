import * as lodash from 'lodash';
import { Pool } from 'pg';

console.log('TypeScript webapp starting...');

const numbers = [1, 2, 3, 4, 5, 6];
const chunks = lodash.chunk(numbers, 2);

console.log('Chunked numbers:', chunks);

// Test pg import (circular dependency package)
// Note: We're not actually connecting, just testing that the module loads
const pool = new Pool({
  // These are dummy config values, we won't actually connect
  host: 'localhost',
  port: 5432,
  database: 'test'
});

console.log('✅ PG Pool created (testing circular dependency resolution)');
console.log('✅ TypeScript webapp built and running successfully!');