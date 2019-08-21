import { module, test } from 'qunit';
import { visit, currentURL, find } from '@ember/test-helpers';
import { setupApplicationTest } from 'ember-qunit';


module('Acceptance | haskell-module', function(hooks) {
  setupApplicationTest(hooks);

  //Test data is in 'server/mocks/packages.js'
  test('visiting /package/test-package-0.1.0.0/show/app/Main.hs', async function(assert) {
    await visit('/package/test-package-0.1.0.0/show/app/Main.hs');

    assert.equal(currentURL(), '/package/test-package-0.1.0.0/show/app/Main.hs');

    const lines = Array.from(find('tbody').children).map((tr) => {
      return tr.children[1].innerText;
    });

    assert.deepEqual(lines,["module Main where",
                           "",
                           "import Lib",
                           "",
                           "main :: IO ()",
                           "main = someFunc",
                           "",
                           ""]);
  });
});
