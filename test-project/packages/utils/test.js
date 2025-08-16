const assert = require('assert');
const { greet, testAllDependencies } = require('./index.js');

function runUtilsTests() {
  console.log('Running utils component tests...');
  
  // Test: Utils basic functionality
  const greeting = greet('Component');
  assert.strictEqual(greeting, 'Hello, Component!', 'greet function should work correctly');
  console.log('✓ Utils greet function works correctly');
  
  // Test: All dependency types work from within utils component
  const depResults = testAllDependencies();
  
  assert(depResults.lodashWorks, 'Lodash should work correctly');
  console.log('✓ Lodash dependency works in utils component');
  
  assert(depResults.chalkWorks, 'Chalk should work correctly'); 
  console.log('✓ Chalk transitive dependency works in utils component');
  
  assert(depResults.scopedWorks, 'Scoped package should work correctly');
  console.log('✓ @sindresorhus/is scoped dependency works in utils component');
  
  assert(depResults.peerWorks, 'Peer dependencies should work correctly');
  console.log('✓ ReactDOM peer dependency works in utils component');
  
  console.log('\n🎉 Utils component tests passed successfully!');
}

runUtilsTests();