const assert = require('assert');
const lodash = require('lodash');
const chalk = require('chalk');
const is = require('@sindresorhus/is');
const React = require('react');
const ReactDOM = require('react-dom');

console.log('Running utils component tests...');

const chunks = lodash.chunk([1,2,3,4], 2);
assert(chunks.length === 2, 'Lodash should work correctly');
console.log('✓ Lodash dependency works in utils component');

const coloredText = chalk.red('test');
assert(typeof coloredText === 'string', 'Chalk should work correctly');
console.log('✓ Chalk transitive dependency works in utils component');

const isString = is.string('test');
assert(isString === true, 'Scoped package should work correctly');
console.log('✓ @sindresorhus/is scoped dependency works in utils component');

const hasRender = typeof ReactDOM.render === 'function';
assert(hasRender, 'Peer dependencies should work correctly');
console.log('✓ ReactDOM peer dependency works in utils component');

console.log('\n🎉 Utils component tests passed successfully!');
