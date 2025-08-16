const lodash = require('lodash');
const chalk = require('chalk');
const is = require('@sindresorhus/is');
const React = require('react');
const ReactDOM = require('react-dom');

function greet(name) {
  return `Hello, ${name}!`;
}

function testAllDependencies() {
  // Test lodash (regular dependency)
  const chunks = lodash.chunk([1,2,3,4], 2);
  
  // Test chalk (transitive dependencies)  
  const coloredText = chalk.red('test');
  
  // Test scoped package
  const isString = is.string('test');
  
  // Test peer dependencies
  const hasRender = typeof ReactDOM.render === 'function';
  
  return {
    lodashWorks: chunks.length === 2,
    chalkWorks: typeof coloredText === 'string',
    scopedWorks: isString === true,
    peerWorks: hasRender
  };
}

module.exports = { greet, testAllDependencies };