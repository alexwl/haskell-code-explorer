import { module, test } from 'qunit';
import { visit, currentURL, find } from '@ember/test-helpers';
import { setupApplicationTest } from 'ember-qunit';

module('Acceptance | packages', function(hooks) {
  setupApplicationTest(hooks);

  //Test data is in file 'server/mocks/packages.js'
  test('visiting /', async function(assert) {
    await visit('/');
    assert.equal(currentURL(), '/');
    const linkToPackage = find('ul a:first-child');
    assert.equal(linkToPackage.innerText, 'test-package-0.1.0.0');
    assert.equal(linkToPackage.getAttribute('href'), '/package/test-package-0.1.0.0');
  });
});
