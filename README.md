Inofficial extension to fetch transactions from [Monzo](https://monzo.com) for [MoneyMoney.app](http://moneymoney-app.com)

![MoneyMoney screenshot with Monzo accounts](screenshots/monzo-accounts.png)

Requirements
----------------

* [Monzo Account](https://monzo.com)
* [MoneyMoney.app](http://moneymoney-app.com) (>= 2.3.5 - April 2018 still in beta)
* As the Monzo API is still in beta, I need to manually add your Monzo UserID to the Monzo OAuth client application, or you need to create your own client app. See [Add Account] for details.

To Dos
---------
* Support Monzo's pods


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

* The OAuth flow has been integrated in MoneyMoney. Make sure you use MoneyMoney >= 2.3.5
* To allow fetching data from Monzo, there needs to be a Monzo Client app. There are 2 options right now:
  
	1. you can either let me know your userID and I'll add it to mine
	2. you can create your own client app and add the clientID and clientSecret in the Monzo.lua script
	
*	Once installed, a Monzo account can be added via *Konto* > *Konto hinzufügen*.

Feedback
---------------------

Feel free to create a Github [Ticket](https://github.com/diederich/moneymoney-monzo/issues/new) for feedback / questions.
