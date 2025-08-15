const assert = require('assert');

function runTests() {
  console.log('Running automated tests for lodash package...');
  
  // Test 1: lodash module loads successfully
  const lodash = require('./result/lodash.js');
  console.log('✓ lodash import successful');
  
  // Test 2: lodash.chunk works correctly
  const chunkResult = lodash.chunk([1,2,3,4,5], 2);
  const expectedChunk = [[1,2], [3,4], [5]];
  assert.deepStrictEqual(chunkResult, expectedChunk, 'chunk result should match expected output');
  console.log('✓ lodash.chunk works correctly');
    
  console.log('\n🎉 All tests passed successfully!');
}

runTests();
