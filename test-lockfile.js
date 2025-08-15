const assert = require('assert');

function runLockfileTests() {
  console.log('Running lockfile-driven tests...');
  
  // Test: Dynamic lodash derivation works
  const lodash = require('./result/lodash.js');
  console.log('✓ Lockfile-generated lodash import successful');
  
  const chunkResult = lodash.chunk([1,2,3,4,5], 2);
  const expectedChunk = [[1,2], [3,4], [5]];
  assert.deepStrictEqual(chunkResult, expectedChunk, 'chunk result should match expected output');
  console.log('✓ Lockfile-generated lodash.chunk works correctly');
  
  console.log('\n🎉 All lockfile-driven tests passed successfully!');
}

runLockfileTests();