# haskell-code-explorer

## Prerequisites
* [Node.js](https://nodejs.org/) (with NPM)
* [Ember CLI](https://ember-cli.com/)
* [bower](https://bower.io/)

## Installation
* `cd haskell-code-explorer/javascript`
* `npm install`
* `bower install`

## Running / Development
* Start haskell-code-server on port 8080
* `ember server --port=4200 --proxy=http://localhost:8080`
* Visit your app at [http://localhost:4200](http://localhost:4200).

To test the app with real-world data :
* ember server --proxy=https://haskell-code-explorer.mfix.io/

## Running Tests
* `ember server --port=4200`
* Open [http://localhost:4200/tests](http://localhost:4200/tests) in a browser

## Building
* `ember build --environment production`
