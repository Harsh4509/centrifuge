# Gnosis_Safe_Audit_Report_1_3_0_Final

[Original PDF](../../../../../../../../centrifuge__protocol-internal/lib/safe-utils/lib/safe-smart-account/docs/Gnosis_Safe_Audit_Report_1_3_0_Final.pdf)

Page numbers below count PDF pages, including covers. Fixed-width text preserves table columns and code indentation.

## PDF page 1

```text
Security Review of
        Gnosis Safe 1.3.0
                 May 2021
```

## PDF page 2

```text
Gnosis Safe 1.3.0 / May 2021
Files in scope
All solidity files in:

https://github.com/gnosis/safe-contracts/tree/ad6c7355d5bdf4f7fa348fbfcb9f07431769a3c9


Current status
No serious issues have been discovered.




1 G0 GROUP // Gnosis Safe 1.3.0 / May 2021
```

## PDF page 3

```text
Report

Issues
No issues have been discovered.


Notes
   1. In ReentrencyTransactionGuard.sol it might be useful to track the active status for each caller
      separately so that the same guard contract can be used for multiple wallets in the same transaction.




2 G0 GROUP // Gnosis Safe 1.3.0 / May 2021
```
