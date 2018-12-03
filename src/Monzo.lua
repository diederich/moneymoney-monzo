-- Inofficial Monzo Extension (www.monzo.com) for MoneyMoney
-- Fetches available data from Monzo API
--
-- Username: Monzo API Key
-- Password: Monzo API Secret
--
-- Copyright (c) 2018 @PvF
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
* Add Monzo's `pods`
-- ]]

local BANK_CODE = "Monzo"

WebBanking {
  version = 0.91,
  url = "https://api.monzo.com",
  services = {BANK_CODE},
  description = string.format(MM.localizeText("Get balance and transactions for %s"), BANK_CODE),
}

-- HTTPS connection object.
local connection

-- Set to true on initial setup to query all transactions
local isInitialSetup = false

function SupportsBank(protocol, bankCode)
    return protocol == ProtocolWebBanking and bankCode == BANK_CODE
end

local clientId
local clientSecret

function InitializeSession2(protocol, bankCode, step, credentials, interactive)
  -- Monzo's authentication uses OAuth2 and want a redirect to their website
  -- see https://monzo.com/docs/#acquire-an-access-token for details
  -- IMPORTANT: Please contact MoneyMoney developer before using OAuth in your own extension.
  if step == 1 then
    clientId = credentials[1]
    clientSecret = credentials[2]

    -- Create HTTPS connection object.
    connection = Connection()

    -- Check if access token is still valid.
    local authenticated = false
    if LocalStorage.accessToken and os.time() < LocalStorage.expiresAt then
      print("Validating access token.")
      local whoami = queryPrivate("ping/whoami")
      authenticated = whoami and whoami["authenticated"]
    end

    -- Obtain OAuth 2.0 authorization code from web browser.
    if not authenticated then
      return {
        title = "Monzo API",
        challenge = "https://auth.monzo.com/" ..
            "?client_id=" .. MM.urlencode(clientId) ..
            "&redirect_uri=" .. MM.urlencode("moneymoney-app://oauth") ..
            "&response_type=code"
        -- The URL argument "state" will be automatically inserted by MoneyMoney.
      }
    end
  end

  if step == 2 then
    local authorizationCode = credentials[1]

    -- Exchange authorization code for access token.
    print("Requesting OAuth access token with authorization code.")
    local postContent = "grant_type=authorization_code" ..
        "&client_id=" .. MM.urlencode(clientId) ..
        "&client_secret=" .. MM.urlencode(clientSecret) ..
        "&redirect_uri=" .. MM.urlencode("moneymoney-app://oauth") ..
        "&code=" .. MM.urlencode(authorizationCode)
    local postContentType = "application/x-www-form-urlencoded"
    local json = JSON(connection:request("POST", "https://api.monzo.com/oauth2/token", postContent, postContentType)):dictionary()
    -- Store access token and expiration date.
    LocalStorage.accessToken = json["access_token"]
    LocalStorage.expiresAt = os.time() + json["expires_in"]

    -- Not really necessary, but allows MoneyMoney to suggest the right country in the account settings as long as Monzo has no IBAN.
    LocalStorage.country = "gb"
  end
end

function ListAccounts(knownAccounts)
  isInitialSetup = true
  local monzoAccountsResponse = queryPrivate("accounts").accounts
  local accounts = {}
  for key, account in pairs(monzoAccountsResponse) do
    accounts[#accounts + 1] = {
      -- String name: Bezeichnung des Kontos
      name = accountNameForMonzoAccountType(account.type),
      -- String owner: Name des Kontoinhabers
      owner = ownerForMonzoAccountOwners(account.owners),
      -- String accountNumber: Kontonummer
      accountNumber = (account.account_number or account.id) .. " ", -- enforces that MoneyMoney will not hide a leading zero
      -- String subAccount: Unterkontomerkmal
      subAccount = account.id,
      -- Boolean portfolio: true für Depots und false für alle anderen Konten
      portfolio = false,
      -- String bankCode: Bankleitzahl
      bankCode = formatSortCode(account.sort_code),
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

function accountNameForMonzoAccountType(monzoAccountTypeString)
  local dict = {
    uk_prepaid = "Monzo Prepaid", -- according to monzo documentation this type does not exist: https://docs.monzo.com/#accounts
    uk_retail = "Monzo",
    uk_retail_joint = "Monzo Joint Account",
  }

  return dict[monzoAccountTypeString] or "Monzo Unknown"
end

function accountTypeForMonzoAccountType(monzoAccountTypeString)
  local dict = {
    uk_prepaid = AccountTypeGiro, -- according to monzo documentation this type does not exist: https://docs.monzo.com/#accounts
    uk_retail = AccountTypeGiro,
    uk_retail_joint = AccountTypeGiro,
  }

  return dict[monzoAccountTypeString] or AccountTypeOther
end

function ownerForMonzoAccountOwners(monzoAccountOwners)
  local result = ""

  for key, owner in pairs(monzoAccountOwners) do
    if key > 1 then
      result = result .. " & "
    end

    result = result .. owner.preferred_name
  end

  return result
end

function formatSortCode(sortCode)
  local result = ""
  if sortCode == nil then
    return result
  end
  for i = 1, #sortCode do
    local char = sortCode:sub(i, i)

    if i > 1 and math.fmod(i, 2) == 1 then
      result = result .. "-"
    end

    result = result .. char
  end

  return result
end

-- Refreshes the account and retrieves transactions
function RefreshAccount(account, since)
  MM.printStatus("Refreshing account " .. account.name)

  local params = {
    account_id = account.subAccount
  }
  params["expand[]"] = "merchant"
  if not isInitialSetup and not (since == nil) then
    -- On first fetch, ignore `since` date, as Monzo actually gives us
    -- all transactions
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
      t[#t + 1] = transaction
    end
  end

  local monzoBalance = queryPrivate("balance", { account_id = account.subAccount })

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
  local isBooked = (not (transaction.settled == nil)) and not (apiDateStrToTimestamp(transaction.settled) == nil)

  local purpose = transaction.description
  if not (transaction.local_currency == transaction.currency) then
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
  if string.len(dateStr) == 0 then
    return nil
  end
  local yearStr, monthStr, dayStr, hourStr, minStr, secStr = string.match(dateStr, "(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d)")
  return os.time({
    year = tonumber(yearStr),
    month = tonumber(monthStr),
    day = tonumber(dayStr),
    hour = tonumber(hourStr),
    min = tonumber(minStr),
    sec = tonumber(secStr)
  })
end

function luaDateToMonzoDate(date)
  -- Mind the exlamation mark which produces UTC
  local dateString = os.date("!%Y-%m-%dT%XZ", date)
  return dateString
end

function EndSession()
end

-- Builds the request for sending to Monzo API and unpacks
-- the returned json object into a table
function queryPrivate(method, params)
  local path = string.format("/%s", method)

  if not (params == nil) then
    local queryParams = httpBuildQuery(params)
    if string.len(queryParams) > 0 then
      path = path .. "?" .. queryParams
    end
  end

  local headers = {}
  headers["Authorization"] = "Bearer " .. LocalStorage.accessToken
  headers["Accept"] = "application/json"

  content = connection:request("GET", url .. path, nil, nil, headers)

  return JSON(content):dictionary()
end

function httpBuildQuery(params)
  local str = ''
  for key, value in pairs(params) do
    str = str .. key .. "=" .. value .. "&"
  end
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
  l = (l) or 100; i = i or ""; -- default item limit, indent string
  if (l < 1) then print "ERROR: Item limit reached."; return l - 1 end;
  local ts = type(s);
  if (ts ~= "table") then print(i, ts, s); return l - 1 end
  print(i, ts); -- print "table"
  for k, v in pairs(s) do -- print "[KEY] VALUE"
    l = RecPrint(v, l, i .. "\t[" .. tostring(k) .. "]");
    if (l < 0) then break end
  end
  return l
end

-- SIGNATURE: MC0CFEgMBsbYgKX6rf0Nf2DWH3duMQasAhUAjKviTQ0sMlHUdpPmqmTfT2cMKZA=
