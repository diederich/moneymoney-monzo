-- Inofficial Monzo Extension (www.monzo.com) for MoneyMoney
-- Fetches available data from Monzo API
--
-- Username: Monzo API Key
-- Password: Monzo API Secret
--
-- Copyright (c) 2017 @PvF
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

--[[
TODO
* Implement OAuth2 scheme / write documentation about auth-token
* Add Monzo's `pods`
-- ]]

WebBanking{
  version = 0.90,
  url = "https://api.monzo.com",
  services= { "Monzo Account" },
  description = "Sync via Monzo's API",
}

-- This extension's clientID. Registered with Monzo
local clientId = "..."
-- The OAuth2 tokens
local accessToken
local refreshToken

-- Returned by Monzo API
local userId

function SupportsBank (protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == "Monzo Account"
end

-- Supposed to login and make sure credentials are correct
function InitializeSession (protocol, bankCode, username, username2, password, username3)
	print("InitializeSession - " .. protocol .. " " .. bankCode)

	-- Monzo's authentication uses OAuth2 and want a redirect to their website
	-- see https://monzo.com/docs/#acquire-an-access-token for details
	-- so for now we use the predefined accessToken given via the playground passed via password
  accessToken = password

	local whoami = queryPrivate("ping/whoami")
	local authenticated = whoami["authenticated"] or false
	if not authenticated then 
		return whoami["error_description"] or LoginFailed
	else
		clientId = whoami["client_id"]
		userId = whoami["user_id"]
		return nil
	end
end

function ListAccounts (knownAccounts)
	local monzoAccountsResponse = queryPrivate("accounts").accounts
	local accounts = {}
	for key, account in pairs(monzoAccountsResponse) do
		accounts[#accounts+1] = {
			-- String name: Bezeichnung des Kontos
			name = accountNameForMonzoAccount(account),
			-- String owner: Name des Kontoinhabers
			owner = account.description,
			-- String accountNumber: Kontonummer
			accountNumber = account.id, -- This is not really good, is it?
			-- String subAccount: Unterkontomerkmal
			subAccount = account.type,
			-- Boolean portfolio: true für Depots und false für alle anderen Konten
			portfolio = false,
			-- String bankCode: Bankleitzahl
			-- String currency: Kontowährung
			currency = "GBP",
			-- String iban: IBAN
			-- String bic: BIC
			-- Konstante type: Kontoart; 
			type = accountTypeForMonzoAccountType(account.type)
		}
	end
  return accounts
end

function accountNameForMonzoAccount(account)
	if account.type == "uk_prepaid" then
		return "Monzo Prepaid"
	elseif account.type == "uk_retail" then
		return "Monzo Current"
	else 
		return "Monzo unknown"
	end
end

function accountTypeForMonzoAccountType(monzoAccountString)
	if monzoAccountString == "uk_prepaid" then
		return AccountTypeGiro
	elseif monzoAccountString == "uk_retail" then
		return AccountTypeGiro
	else
		print("Unknown account type: ", monzoAccountString)
		return AccountTypeOther
	end
end

-- Refreshes the account and retrieves transactions
function RefreshAccount (account, since)
	MM.printStatus("Refreshing account " .. account.name)

	local params = {
		account_id = account.accountNumber
	}
	params["expand[]"] = "merchant"
	if not (since == nil) then
		params["since"] = luaDateToMonzoDate(since)
	end
	
	local transactionsResponse = queryPrivate("transactions", params)
	if nil == transactionsResponse.transactions then
		return transactionsResponse.message
	end
	
	local t = {} -- List of transactions to return
  for index, monzoTransaction in pairs(transactionsResponse.transactions) do
		local transaction = transactionForMonzoTransaction(monzoTransaction)
		if transaction == nil then
			print("Skipped transaction: " .. monzoTransaction.description)
		else
			 t[#t+1] = transaction
		end
  end
	
	local monzoBalance = queryPrivate("balance", { account_id = account.accountNumber })
	
  return {
		balance = amountForMonzoAmount(monzoBalance.balance),
		transactions = t
	}
end

function transactionForMonzoTransaction(transaction)
	local isValidTransaction = (transaction.decline_reason == nil) or false
	if not isValidTransaction then
		-- I haven't found a way of marking transactions as invalid,
		-- so we could display the error reason which Monzo provides us with.
		-- One workaround would be to keep the transaction, but set the amount to zero
		return nil
	end
	local isBooked = (not(transaction.settled == nil)) and not (apiDateStrToTimestamp(transaction.settled) == nil) 	
		
	local purpose = transaction.description
	if not(transaction.local_currency == transaction.currency) then
		purpose = purpose .. "\nConverted from " .. amountForMonzoAmount(transaction.local_amount) .. transaction.local_currency
	end
	
	t = {
		-- String name: Name des Auftraggebers/Zahlungsempfängers
		name = nameForTransaction(transaction),
		-- String accountNumber: Kontonummer oder IBAN des Auftraggebers/Zahlungsempfängers
		-- String bankCode: Bankzeitzahl oder BIC des Auftraggebers/Zahlungsempfängers
		-- Number amount: Betrag
		amount = amountForMonzoAmount(transaction.amount),
		-- String currency: Währung
		currency = transaction.currency,
		-- Number bookingDate: Buchungstag; Die Angabe erfolgt in Form eines POSIX-Zeitstempels.
	  bookingDate = apiDateStrToTimestamp(transaction.created),
		-- Number valueDate: Wertstellungsdatum; Die Angabe erfolgt in Form eines POSIX-Zeitstempels.
	  valueDate = apiDateStrToTimestamp(transaction.settled),
		-- String purpose: Verwendungszweck; Mehrere Zeilen können durch Zeilenumbrüche ("\n") getrennt werden.
	  purpose = purpose,
		-- Number transactionCode: Geschäftsvorfallcode
		-- Number textKeyExtension: Textschlüsselergänzung
		-- String purposeCode: SEPA-Verwendungsschlüssel
		purposeCode = transaction.category,
		-- String bookingKey: SWIFT-Buchungsschlüssel
		bookingKey = transaction.dedupe_id,
		-- String bookingText: Umsatzart
		bookingText = transaction.notes,
		-- String primanotaNumber: Primanota-Nummer
		-- String customerReference: SEPA-Einreicherreferenz
		-- String endToEndReference: SEPA-Ende-zu-Ende-Referenz
		-- String mandateReference: SEPA-Mandatsreferenz
		-- String creditorId: SEPA-Gläubiger-ID
		-- String returnReason: Rückgabegrund
		returnReason = transaction.decline_reason,
		-- Boolean booked: Gebuchter oder vorgemerkter Umsatz
		booked = isBooked,
	}
	return t
end

function amountForMonzoAmount(amount)
	if amount == nil then 
		return 0 
	end
	return amount / 100
end

function nameForTransaction(transaction) 
	local transactionName
	if transaction.is_load == true then
		transactionName = "Top up"
	elseif not (transaction.merchant == nil) then
		transactionName = transaction.merchant.name
	else
		transactionName = transaction.description
	end
	return transactionName or transaction.description
end

function apiDateStrToTimestamp(dateStr)
	print(dateStr)
	if string.len(dateStr) == 0 then
		return nil
	end
  local yearStr, monthStr, dayStr = string.match(dateStr, "(%d%d%d%d)-(%d%d)-(%d%d)")
  return os.time({
      year = tonumber(yearStr),
      month = tonumber(monthStr),
      day = tonumber(dayStr)
  })
end

function luaDateToMonzoDate(date)
	-- Mind the exlamation mark which produces UTC
	local dateString = os.date("!%Y-%m-%dT%XZ", date)
	return dateString
end

function EndSession ()
end

-- Builds the request for sending to Monzo API and unpacks
-- the returned json object into a table
function queryPrivate(method, params)
  local path = string.format("/%s", method)

  if not (params == nil) then
	  local queryParams = httpBuildQuery(params)
		if string.len(queryParams) > 0 then
			path = path .. "?".. queryParams
		end
  end
		
  local headers = {}
  headers["Authorization"] = "Bearer " .. accessToken
	headers["Accept"] = "application/json"
	
  connection = Connection()
  content = connection:request("GET", url .. path, nil, nil, headers)

  return JSON(content):dictionary()
end

function httpBuildQuery(params)
	print("Build params from ")
	RecPrint(params)
  local str = ''
  for key, value in pairs(params) do
    str = str .. key .. "=" .. value .. "&"
  end
	print(str)
  str = str.sub(str, 1, -2)
	return str
end

-- DEBUG Helpers

--[[ RecPrint(struct, [limit], [indent])   Recursively print arbitrary data. 
	Set limit (default 100) to stanch infinite loops.
	Indents tables as [KEY] VALUE, nested tables as [KEY] [KEY]...[KEY] VALUE
	Set indent ("") to prefix each line:    Mytable [KEY] [KEY]...[KEY] VALUE
--]]
function RecPrint(s, l, i) -- recursive Print (structure, limit, indent)
	l = (l) or 100; i = i or "";	-- default item limit, indent string
	if (l<1) then print "ERROR: Item limit reached."; return l-1 end;
	local ts = type(s);
	if (ts ~= "table") then print (i,ts,s); return l-1 end
	print (i,ts);           -- print "table"
	for k,v in pairs(s) do  -- print "[KEY] VALUE"
		l = RecPrint(v, l, i.."\t["..tostring(k).."]");
		if (l < 0) then break end
	end
	return l
end

-- SIGNATURE: MC0CFQCV3H3eb8PxyYdkbY9ocmTL1cZ4KwIUNR7XZ70dzy9O+K1Q/tRgfmK8mk0=
