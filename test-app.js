const lodash = require('./result/lodash.js');

console.log('Testing lodash import...');
console.log('lodash.chunk([1,2,3,4,5], 2):', lodash.chunk([1,2,3,4,5], 2));
console.log('lodash.uniq([1,1,2,3,3]):', lodash.uniq([1,1,2,3,3]));
console.log('lodash.capitalize("hello world"):', lodash.capitalize("hello world"));

console.log('✓ Lodash import and usage successful!');