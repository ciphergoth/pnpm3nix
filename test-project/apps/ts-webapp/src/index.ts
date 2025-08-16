import * as lodash from 'lodash';

console.log('TypeScript webapp starting...');

const numbers = [1, 2, 3, 4, 5, 6];
const chunks = lodash.chunk(numbers, 2);

console.log('Chunked numbers:', chunks);
console.log('✅ TypeScript webapp built and running successfully!');