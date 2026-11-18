#!/usr/bin/env python3
"""Generate the public Gavel V2 testnet address list from the deployment records.

The list is generated, never typed. Run:

    python script/v2-addresses/generate.py \
        --core <core record.md> --products <products record.md> \
        --markets <markets record.md> --bond <bond record.md>

It reads only each record's contract, token, spot-pair and bill-series tables,
and writes docs/v2-testnet-addresses.md and docs/v2-testnet-addresses.json.
It fails if a record names a contract this script does not classify, so a new
deployment cannot slip into the list unlabelled. Standard library only.
"""

import argparse
import json
import re
import sys
from pathlib import Path

CHAIN = "Arbitrum Sepolia"
CHAIN_ID = 421614
EXPLORER = "https://sepolia.arbiscan.io/address/"
ADDR = re.compile(r"0x[0-9a-fA-F]{40}")

# name -> (group, role). Groups are listed in this order.
GROUPS = ["Core", "Engines", "Bullet loan", "Spot market", "Secondary market",
          "Cash-settled future", "Insurance and bills", "Liquidation cover",
          "BOND", "Test contracts"]

CLASSIFY = {
    "Vault": ("Core", "The shared vault"),
    "ObligationLogic": ("Core", "Library linked into Obligation"),
    "ModuleLogic": ("Core", "Library linked into Obligation"),
    "Obligation": ("Core", "Obligations and their claim units (ERC-1155)"),
    "ObligorPosition": ("Core", "Obligor positions (ERC-721)"),
    "Lien": ("Core", "The TAKE-only Lien"),
    "SingleAuction": ("Engines", "Engine"),
    "GroupAuction": ("Engines", "Engine"),
    "PostedOffer": ("Engines", "Engine"),
    "BatchAuction": ("Engines", "Engine"),
    "ClockAuction": ("Engines", "Engine"),
    "SealedFront": ("Engines", "Sealed-bid helper (not an engine)"),
    "BulletOpening": ("Bullet loan", "Library linked into both products"),
    "BulletSettlement": ("Bullet loan", "Library linked into both products"),
    "BulletLoanRequest": ("Bullet loan", "Requests, to one lender or many"),
    "BulletLoanOffer": ("Bullet loan", "Offers, to one borrower or many"),
    "LotCreditIndex": ("Secondary market", "Library linked into ClaimLotMarket"),
    "ClaimLotMarket": ("Secondary market", "Sales of claim units"),
    "ObligorPositionMarket": ("Secondary market", "Sales of obligor positions"),
    "SpotReferenceResolver": ("Cash-settled future", "Reference-price resolver"),
    "FutureOrchestrator": ("Cash-settled future", "Offers and futures"),
    "CoverIssuance": ("Insurance and bills", "Library linked into CoverOrchestrator"),
    "CoverSettlement": ("Insurance and bills", "Library linked into CoverOrchestrator"),
    "CoverOrchestrator": ("Insurance and bills", "Cover offers and policies"),
    "ContingentBondAdapter": ("Insurance and bills", "Adapter for BOND stakes on cover"),
    "BillPackager": ("Insurance and bills", "Packages insured claims into weekly bills"),
    "MorphoCoverAdapter": ("Liquidation cover", "Adapter, one per ceiling"),
    "CoverAccount": ("Liquidation cover", "Implementation cloned for each covered account"),
    "BondListing": ("BOND", "Lists; holds the listing power"),
    "BondToken": ("BOND", "The BOND token"),
    "BondCurve": ("BOND", "Rate curves"),
    "BondProtocol": ("BOND", "Registrations, stakes and minting"),
    "BondValuation": ("BOND", "First BOND package"),
    "AuctionOrchestrator": ("Bullet loan", "First loan auction contract"),
    "MockMorpho": ("Test contracts", "Test copy of a lending market"),
    "MockOracle": ("Test contracts", "Test lending market's oracle"),
    "MockIrm": ("Test contracts", "Test lending market's rate model"),
    "MockCoverAdapter": ("Test contracts", "Test cover adapter"),
}

# Contracts in the core record replaced by later deployments.
SUPERSEDED_CORE = {"Obligation", "ObligorPosition", "Lien", "AuctionOrchestrator"}
# Contracts in the products record replaced by the BOND record.
SUPERSEDED_PRODUCTS = {"BondValuation", "BondToken", "BondProtocol"}


def section(text, heading):
    """Return the lines of a '## heading' section, up to the next '## '."""
    lines = text.splitlines()
    out, inside = [], False
    for line in lines:
        if line.startswith("## "):
            if inside:
                break
            inside = line[3:].strip().lower().startswith(heading.lower())
            continue
        if inside:
            out.append(line)
    if not inside and not out:
        sys.exit(f"section '{heading}' not found")
    return out


def table(lines):
    """Parse the first markdown table in lines into a list of dicts."""
    rows, header = [], None
    for line in lines:
        if not line.startswith("|"):
            if header:
                break
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if header is None:
            header = [h.lower() for h in cells]
        elif set(line.replace("|", "").strip()) <= set("-: "):
            continue
        else:
            rows.append(dict(zip(header, cells)))
    if not rows:
        sys.exit("empty table")
    return rows


def addr(cell):
    m = ADDR.search(cell)
    if not m:
        sys.exit(f"no address in '{cell}'")
    return m.group(0).lower()


def contract_name(cell):
    return cell.split("(")[0].strip()


def entry(name, address, status, note=""):
    if name not in CLASSIFY:
        sys.exit(f"unclassified contract '{name}': add it to CLASSIFY")
    group, role = CLASSIFY[name]
    return {"group": group, "name": name, "role": role, "address": address,
            "status": status, "note": note}


def main():
    ap = argparse.ArgumentParser()
    for k in ("core", "products", "markets", "bond"):
        ap.add_argument(f"--{k}", required=True, type=Path)
    ap.add_argument("--out", default=Path(__file__).resolve().parents[2] / "docs", type=Path)
    a = ap.parse_args()
    core, products, markets, bond = (p.read_text(encoding="utf-8") for p in (a.core, a.products, a.markets, a.bond))

    contracts, tokens = [], []

    for r in table(section(core, "Contracts")):
        n = contract_name(r["contract"])
        contracts.append(entry(n, addr(r["address"]), "superseded" if n in SUPERSEDED_CORE else "current"))

    for r in table(section(core, "Tokens")):
        tokens.append({"symbol": r["symbol"], "name": r["name"], "decimals": int(r["decimals"]),
                       "address": addr(r["address"])})

    pairs = table(section(markets, "Spot pairs"))
    series = table(section(markets, "The bill's series markets"))
    market_label = {addr(p["spotmarket"]): f"Pair {p['pair']}" for p in pairs}
    market_label.update({addr(s["spotmarket"]): f"Bill series {s['series']}" for s in series})

    for r in table(section(products, "Contracts")):
        n = contract_name(r["contract"])
        a_ = addr(r["address"])
        if n == "SpotMarket":
            continue  # listed from the markets record below
        contracts.append(entry(n, a_, "superseded" if n in SUPERSEDED_PRODUCTS else "current"))

    for r in table(section(bond, "Contracts")):
        n = contract_name(r["contract"])
        contracts.append(entry(n, addr(r["address"]), "current"))

    spot = [{"pair": p["pair"], "marketId": int(p["market id"]), "address": addr(p["spotmarket"]),
             "base": addr(p["base (decimals)"]), "quote": addr(p["quote (decimals)"])} for p in pairs]
    bills = [{"series": int(s["series"]), "date": s["date (utc)"].split()[-1], "marketId": int(s["market id"]),
              "spotMarket": addr(s["spotmarket"]), "billToken": addr(s["billtoken"])} for s in series]

    seen = {}
    for c in contracts + [{"name": "SpotMarket", "address": s["address"]} for s in spot] + \
            [{"name": "SpotMarket", "address": b["spotMarket"]} for b in bills]:
        if c["address"] in seen and seen[c["address"]] != c["name"]:
            sys.exit(f"address {c['address']} listed twice")
        seen[c["address"]] = c["name"]

    data = {"chain": CHAIN, "chainId": CHAIN_ID, "explorer": EXPLORER,
            "contracts": contracts, "spotMarkets": spot, "billSeries": bills, "tokens": tokens}
    a.out.mkdir(parents=True, exist_ok=True)
    (a.out / "v2-testnet-addresses.json").write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    (a.out / "v2-testnet-addresses.md").write_text(render(data), encoding="utf-8")
    print(f"{len(contracts)} contracts, {len(spot)} pairs, {len(bills)} bill series, {len(tokens)} tokens")


def link(a):
    return f"[`{a}`]({EXPLORER}{a}#code)"


def render(d):
    tok = {t["address"]: t["symbol"] for t in d["tokens"]}
    out = [
        "# Gavel V2 testnet addresses",
        "",
        "<!-- Generated by script/v2-addresses/generate.py. Do not edit by hand. -->",
        "",
        f"Gavel V2 on **{d['chain']}** (chain id {d['chainId']}). These contracts are deployed for testing and are "
        "**not audited**. The tokens are test tokens with no value. Each address links to Arbiscan. "
        "Every contract in this list other than the test tokens has verified source there. A machine-readable copy is in [`v2-testnet-addresses.json`](v2-testnet-addresses.json).",
        "",
        "Every owned contract on the testnet is owned by the account that deployed it; `owner()` returns it.",
        "",
        "How these contracts work: [Gavel developer docs](https://github.com/JamieFrame/gavel-developer-docs/tree/main/v2).",
        "",
    ]
    current = [c for c in d["contracts"] if c["status"] == "current"]
    for g in GROUPS:
        rows = [c for c in current if c["group"] == g]
        if g == "Spot market":
            out += [f"## {g}", "", "One `SpotMarket` per pair, on `BatchAuction`.", "",
                    "| Pair | Market id | `SpotMarket` |", "|---|---|---|"]
            out += [f"| {s['pair']} | {s['marketId']} | {link(s['address'])} |" for s in d["spotMarkets"]]
            out.append("")
            continue
        if not rows:
            continue
        out += [f"## {g}", "", "| Contract | Role | Address |", "|---|---|---|"]
        out += [f"| `{c['name']}` | {c['role']} | {link(c['address'])} |" for c in rows]
        out.append("")
        if g == "Insurance and bills":
            out += ["### Bill series", "",
                    "Each series has a `SpotMarket` (the bill against the settlement token) and a `BillToken`, "
                    "whose address is fixed in advance and which is created at the series' first deposit, so it "
                    "may not exist on chain yet.", "",
                    "| Series | Matures (UTC) | Market id | `SpotMarket` | `BillToken` |", "|---|---|---|---|---|"]
            out += [f"| {b['series']} | {b['date']} | {b['marketId']} | {link(b['spotMarket'])} | `{b['billToken']}` |"
                    for b in d["billSeries"]]
            out.append("")
    out += ["## Test tokens", "",
            "Mock ERC-20s for the testnet. Anyone can `mint` them, and anyone can `burn` any holder's balance, "
            "the vault's included. They are worth nothing.", "",
            "| Symbol | Name | Decimals | Address |", "|---|---|---|---|"]
    out += [f"| {t['symbol']} | {t['name']} | {t['decimals']} | {link(t['address'])} |" for t in d["tokens"]]
    out.append("")
    sup = [c for c in d["contracts"] if c["status"] == "superseded"]
    out += ["## Superseded", "",
            "Deployed earlier and still on chain, but replaced by the contracts above. The first `Obligation`, "
            "`Lien` and `AuctionOrchestrator` remain on the vault's consumer whitelist. The developer "
            "docs describe the current contracts.", "", "| Contract | Was | Address |", "|---|---|---|"]
    out += [f"| `{c['name']}` | {c['role'] if c['name'] in ('BondValuation', 'AuctionOrchestrator') else 'First ' + c['name']} | {link(c['address'])} |"
            for c in sup]
    out.append("")
    return "\n".join(out)


if __name__ == "__main__":
    main()
