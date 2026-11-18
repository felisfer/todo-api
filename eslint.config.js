const js = require('@eslint/js');
const globals = require('globals');

module.exports = [
  { ignores: ['coverage/', 'node_modules/', 'infra/'] },
  js.configs.recommended,
  {
    languageOptions: {
      ecmaVersion: 2024,
      sourceType: 'commonjs',
      globals: { ...globals.node },
    },
  },
  {
    files: ['tests/**'],
    languageOptions: { globals: { ...globals.jest } },
  },
];
