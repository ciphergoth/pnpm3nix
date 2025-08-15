const assert = require('assert');

function runProjectTests() {
  console.log('Running test-project tests...');
  
  // Test: Can import lodash from node_modules
  const lodash = require('lodash');
  console.log('✓ Lodash import successful from node_modules');
  
  // Test: Lodash functionality works
  const chunkResult = lodash.chunk([1,2,3,4,5], 2);
  const expectedChunk = [[1,2], [3,4], [5]];
  assert.deepStrictEqual(chunkResult, expectedChunk, 'chunk result should match expected output');
  console.log('✓ Lodash functionality works correctly');
  
  // Test: Can import chalk from node_modules
  const chalk = require('chalk');
  console.log('✓ Chalk import successful from node_modules');
  
  // Test: Chalk functionality works (should produce colored text)
  const redText = chalk.red('test');
  assert(typeof redText === 'string', 'chalk.red should return a string');
  assert(redText.includes('test'), 'chalk output should contain the input text');
  console.log('✓ Chalk functionality works correctly');
  
  console.log('\n🎉 Project tests passed successfully!');
}

runProjectTests();