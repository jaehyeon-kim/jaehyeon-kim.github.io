// Copy of the theme's file of the same name, at v1.13.3. Since Hugo 0.161.0, Node runs
// with its permission model and may read only the project, the assets directories and
// node_modules, so it cannot load this file, or the one it requires, from the theme in
// the module cache. A copy in the project root takes precedence over the theme's.

const autoprefixer = require('autoprefixer');

module.exports = {
  plugins: [
    autoprefixer,
    ...process.env.HUGO_ENVIRONMENT === 'production'
      ? [require('./purgecss.config.js').default]
      : [],
  ]
}
