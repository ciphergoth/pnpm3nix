const assert = require('assert');

function runDependencyTests() {
  console.log('Running dependency symlink tests...');
  
  // Test: Mock package can import and use lodash via symlink
  const mockPackage = require('./result/index.js');
  console.log('✓ Mock package import successful');
  
  const testResult = mockPackage.testLodashImport();
  assert.strictEqual(testResult.success, true, 'testLodashImport should return success: true');
  assert.deepStrictEqual(testResult.chunkResult, [[1,2], [3,4]], 'chunk result should match expected output');
  console.log('✓ Lodash dependency works through symlink');
  
  console.log('\n🎉 All dependency tests passed successfully!');
}

runDependencyTests();