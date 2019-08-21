import { module, test } from 'qunit';
import { visit, currentURL, find } from '@ember/test-helpers';
import { setupApplicationTest } from 'ember-qunit';


module('Acceptance | package', function(hooks) {
  setupApplicationTest(hooks);

  //Test data is in 'server/mocks/packages.js'
  test('visiting /package/test-package-0.1.0.0', async function(assert) {
    await visit('/package/test-package-0.1.0.0');
    assert.equal(currentURL(), '/package/test-package-0.1.0.0');

    const moduleNames = Array.from(find('ul.modules').children).map((li) => {
      return [li.innerText,li.children[0].getAttribute('href')];
    });

    assert.deepEqual(moduleNames,[["app/Main.hs","/package/test-package-0.1.0.0/show/app/Main.hs"],
                                 ["src/Lib.hs","/package/test-package-0.1.0.0/show/src/Lib.hs"],
                                 ["src/Types.hs","/package/test-package-0.1.0.0/show/src/Types.hs"],
                                 ["test/Spec.hs","/package/test-package-0.1.0.0/show/test/Spec.hs"]]);
  });
});
