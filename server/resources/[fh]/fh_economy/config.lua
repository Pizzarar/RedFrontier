FhEconomyConfig = {
    moneyType = 'cash',   -- RSGCore money account credited by pay()
    maxPay = 100000,      -- sanity cap on a single payout
    maxRepDelta = 1000,   -- sanity cap on a single rep change (abs)
    maxReason = 128,      -- max reason length (matches fh_ledger.reason varchar(128))
    repMin = -10000,
    repMax = 10000,
}
