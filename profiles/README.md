# Supported-game boundary metadata

`agmp-v16.entries` contains 1,312 corroborating function-start addresses for
Splatoon EUR AGMP01 v16, RPX SHA-256
`45ECD1ED81A97F46B1C8AE24820CD47FBC55399B50AF09BF1F9050FE803308E5`.

This is address metadata only: no PowerPC instructions, C++ implementations,
assets or save data. RebrewU checks references, control flow and non-fallthrough
separators in the user's RPX before accepting these boundaries. Setup supplies
the profile with `--analyzer-entries`, after checking the RPX hash.

The profile restores the same 96,300 registered entries as the maintained game
generation. Omitting it produces only 94,988 entries, leaving indirect callbacks
unavailable. Setup includes the profile hash in its generation-cache key and
rejects incomplete function tables.
