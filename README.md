Inofficial extension to fetch transactions from [Monzo](https://monzo.com) for [MoneyMoney.app](http://moneymoney-app.com)

![MoneyMoney screenshot with Monzo accounts](screenshots/monzo-accounts.png)

Requirements
----------------

* [Monzo Account](https://monzo.com)
* [MoneyMoney.app](http://moneymoney-app.com)
* Access Token: The plugin needs an access token for the Monzo API. Given this is still in beta, it's kind of  a hack but works. See [Add account] for details.

To Dos
---------

* Improve access token query / login behaviour
* use refresh token for, well, refreshing the access token

Installation
------------

### Signed copy from Extensions Page

[TBD]

### Usigned copy from the GitHub-Repository

* Copy the `Monzo.lua` file from src into MoneyMoney's Extension folder
  * Open MoneyMoney.app
	* Tap "Hilfe", "Show Database in Finder"
	* Copy `Monzo.lua` into Extensions Folder
* Disable Signature Check (Needs beta Version!)
  * Open MoneyMoney.app
	* Enable Beta-Updates
	* Install update
	* Go to "Extensions"-tab
	* Allow unsigned extensions

Add account
-------------------

Once installed, a Monzo account can be added via *Konto* > *Konto hinzufügen*.
Use the access token for the password (username is not used).

Aquire access token via Monzo website:

* Go to their developer website
* Login via link sent by email
* copy the access token from the playground

Aquire access token via Webapp (Monzo API beta program - somewhat unfinished):

* let me know your Monzo user ID, it needs to be added to the app
* I created a simple helper to extract the tokens via AWS Labmdas. They're never stored, but only displayed in your browser and can then be copied to the extension: https://gu5soke45j.execute-api.eu-central-1.amazonaws.com/beta/moneymoney-monzo-oauth/init


Feedback
---------------------

Feel free to create a Github [Ticket](https://github.com/diederich/moneymoney-monzo/issues/new) for feedback / questions.
