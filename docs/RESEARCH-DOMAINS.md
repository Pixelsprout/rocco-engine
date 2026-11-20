# Research: a domain for rocco

Date: 2026-11-20

## Question

Which domains for rocco are free to register? What does each cost per year
to buy and to renew? Which names are premium? Which other projects called
"rocco" can confuse a search? The site will be hosted on Vercel.

This document decides nothing. Nothing was bought, and no personal details
were entered anywhere.

## Method

- Registration status comes from the registry itself. For gTLDs and `.dev`,
  the query went to the registry RDAP server named in the IANA bootstrap file
  ([data.iana.org/rdap/dns.json][iana-rdap]). An HTTP 404 with the body
  `"<name> not found"` means the registry has no record. A 200 means the name
  is registered.
- `.gg`, `.so`, `.sh` and `.io` have no RDAP service in the IANA bootstrap.
  For those, the query went to the registry WHOIS server (`whois.gg`,
  `whois.nic.so`, `whois.nic.sh`, `whois.nic.io`).
- Every free name also has no NS or SOA record in DNS (`dig`).
- The list of TLDs that exist comes from the IANA root zone list
  ([tlds-alpha-by-domain.txt][iana-tlds], version 2026111900).
- Porkbun prices come from Porkbun's public pricing API
  (`POST https://api.porkbun.com/api/json/v3/pricing/get`, no key). These are
  standard TLD prices. They do not show premium names.
- Vercel prices come from `vercel domains price` and `vercel domains check`
  (Vercel CLI 54.9.0). These are read-only quotes for the exact name, so they
  do show premium prices. Vercel is the planned host, so a Vercel purchase
  needs no DNS transfer.
- Cloudflare does not publish a price page that a script can read
  (`domains.cloudflare.com/tlds` returns 403). The supported-TLD list comes
  from [cloudflare.com/tld-policies][cf-tld]. The prices come from the
  third-party tracker [CostGoat][costgoat] (checked 2026-10-20). Treat them as
  secondary.
- Namecheap blocks automated fetches (403). Namecheap prices come from the
  third-party tracker [domainoffer.net][do-nc-dev] (updated 2026-11-20).
  Treat them as secondary. They are the prices without a promo code.

All prices are USD per year. Cloudflare sells at registry cost with no markup,
so its prices are the floor for a TLD it supports.

## Results: free names

| Domain | Free? | Vercel buy / renew | Porkbun buy / renew | Cloudflare buy / renew | Namecheap buy / renew | Note |
|---|---|---|---|---|---|---|
| roccoengine.dev | yes | 9.99 / 13.00 | 8.75 / 12.87 | 8.20 / 12.20 | 10.98 / 20.98 | standard price |
| rocco-engine.dev | yes | 9.99 / 13.00 | 8.75 / 12.87 | 8.20 / 12.20 | 10.98 / 20.98 | standard price |
| roccogames.dev | yes | 9.99 / 13.00 | 8.75 / 12.87 | 8.20 / 12.20 | 10.98 / 20.98 | standard price |
| playrocco.dev | yes | 9.99 / 13.00 | 8.75 / 12.87 | 8.20 / 12.20 | 10.98 / 20.98 | standard price |
| roccoengine.com | yes | 12.03 / 12.03 | 11.81 / 11.81 | 10.46 / 10.46 | 12.08 / 19.98 | standard price |
| rocco-engine.com | yes | 12.03 / 12.03 | 11.81 / 11.81 | 10.46 / 10.46 | 12.08 / 19.98 | standard price |
| roccogames.com | yes | 12.03 / 12.03 | 11.81 / 11.81 | 10.46 / 10.46 | 12.08 / 19.98 | standard price |
| playrocco.com | yes | not quoted | 11.81 / 11.81 | 10.46 / 10.46 | 12.08 / 19.98 | standard price |
| roccoengine.org | yes | 9.99 / 10.99 | 7.98 / 11.84 | 8.50 / 11.20 | 8.48 / 18.98 | standard price |
| rocco-engine.org | yes | 9.99 / 10.99 | 7.98 / 11.84 | 8.50 / 11.20 | 8.48 / 18.98 | standard price |
| rocco.games | yes | 14.99 / 31.00 | 8.24 / 30.38 | 26.20 / 26.20 | 11.98 / 47.98 | standard price; renewal is about 2x to 4x the first year |
| rocco.tools | yes | 17.99 / 36.83 | 9.78 / 32.44 | supported, price not read | not read | standard price |
| rocco.build | yes | 30.00 / 30.00 | 26.26 / 26.26 | not supported | not read | standard price |
| rocco.engineer | yes | 17.99 / 42.00 | 9.78 / 35.53 | not read | not read | standard price |
| rocco.engineering | yes | 11.99 / 64.00 | 6.69 / 60.25 | supported, price not read | not read | renewal is high |
| rocco.codes | yes | 7.99 / 62.00 | 4.63 / 63.34 | supported, price not read | not read | renewal is high |
| rocco.zone | yes | 14.99 / 35.00 | 8.24 / 34.50 | not read | not read | standard price |
| rocco.game | yes | 349.99 / 366.77 | 340.37 / 340.37 | not supported | not read | `.game` is expensive for every name |
| rocco.page | yes | **64.90 / 64.90** | standard 10.81 / 10.81 | standard 10.20 / 10.20 | not read | **premium**: Vercel quotes about 6x the `.page` standard price |
| rocco.fun | yes | **68.75 / 275.00** | standard 2.57 / 31.41 | not read | not read | **premium**: Vercel renewal is about 9x the `.fun` standard price |
| rocco.so | registry says not registered | not sold (renew quote 85.99, no buy quote) | not sold | not supported | 64.98 / 68.98 | see the note below |

Standard prices at Porkbun, Cloudflare and Namecheap are TLD list prices. A
registrar can still ask a premium price for one exact name. Only the Vercel
column was quoted for the exact name. Before any purchase, check the exact
name at the chosen registrar.

`rocco.so`: the `.so` registry WHOIS returns "No Object Found". But
`vercel domains check` reports it as not available, and Vercel gives no
purchase price. Porkbun and Cloudflare do not sell `.so`. The registry may hold
the name as reserved or premium. This is not confirmed.

## Results: registered names

| Domain | Registered | Expires | Source |
|---|---|---|---|
| rocco.dev | 2019-02-28 | 2027-02-28 | Google Registry RDAP |
| getrocco.dev | **2026-11-08** | 2027-11-08 | Google Registry RDAP |
| rocco.app | 2018-05-14 | 2027-05-14 | Google Registry RDAP |
| rocco.run | 2023-02-25 | 2033-02-25 | Identity Digital RDAP |
| rocco.studio | registered | | Identity Digital RDAP |
| rocco.software | registered | | Identity Digital RDAP |
| rocco.gg | 2025-02-25 | renews each 25 February | `whois.gg` (registrar Spaceship, Cloudflare DNS) |
| rocco.sh | 2021-02-03 | 2027-02-03 | `whois.nic.sh` (registrar 1API) |
| rocco.io | 2015-09-17 | 2027-09-17 | `whois.nic.io` (registrar Namecheap) |
| rocco.xyz | registered | | CentralNic RDAP |
| rocco.lol | registered | | CentralNic RDAP |
| rocco.land | registered | | Identity Digital RDAP |
| getrocco.com | registered | | Verisign RDAP |
| rocco.com | registered | | Verisign RDAP |
| rocco.org | registered | | PIR RDAP |
| rocco.tech | not registered, but **"Registry Blocked"** | | `whois.nic.tech`; Vercel quotes a 1100.00 renewal |

`getrocco.dev` was registered 12 days before this check. If the owner did not
register it, someone else took it recently.

## TLDs that fit a game engine

From the IANA root zone list (version 2026111900):

- `.engine` and `.engines` do not exist.
- `.game` and `.games` exist. `.game` costs about 340 to 367 per year for any
  name. `.games` costs 8 to 15 the first year and 26 to 48 to renew.
- `.play` exists, but Porkbun and Cloudflare do not sell it. It is a Google
  Registry TLD.
- `.dev`, `.tools`, `.build`, `.codes`, `.engineering`, `.engineer`,
  `.software` and `.studio` exist.
- `.gg` exists and is popular for games. `rocco.gg` is taken. The `.gg`
  standard price at Porkbun is 51.80 / 51.80.

`.dev` and `.app` are on the HSTS preload list for the whole TLD, so a site
on them must use HTTPS. Vercel serves HTTPS by default, so this costs nothing.

## Name clashes

No other game engine called "rocco" was found. The names that can confuse a
search:

- **Rocco, Docco in Ruby** ([rtomayko/rocco][rtomayko], 402 stars). A
  literate-programming doc tool. The repository is archived. The last
  `rocco` gem release is 0.8.2 (2011). It still holds the `rocco` gem name
  and ranks high for "rocco github".
- **`rocco` crate** ([crates.io/crates/rocco][crate]): a Docco-style
  literate-programming library in Rust, last updated 2020-11-06.
- **`rocco` on npm** ([registry.npmjs.org/rocco][npm]): a small dependency
  injector, last modified 2022-06-26.
- **`rocco` on PyPI** ([pypi.org/project/rocco][pypi]): a peak-calling tool
  for genomics, version 1.14.0.
- **Games**: *Seasons of Rocco* (2024, Steam [app 2700510][seasons]),
  *Rocco's Island: Ring to End the Pain* (2022, [Steam][island]) and *Rocco*
  (1985, a ZX Spectrum boxing game, [MobyGames][moby]).
- **Roc engines**: [a11ce/roc][a11ce] and [bsgbryan/Amber][amber] call
  themselves a "Roc" game engine. These are not the Roc language. They can
  appear near rocco in a search for "roc game engine".
- **Ignacio Rocco** has several popular computer-vision repositories on
  GitHub (for example `ignacio-rocco/detectorch`, 558 stars). These rank
  first in a GitHub search for "rocco".

"rocco" alone is a common name, so a search for "rocco" will not find the
engine. "rocco engine" and "rocco roc" have no strong clash. A domain that
includes "engine" helps search for the same reason.

## Summary

The cheapest names that fit and renew at a normal price:

1. `roccoengine.dev` or `rocco-engine.dev`: 8.20 to 9.99 the first year,
   12.20 to 13.00 to renew (Namecheap renews at 20.98).
2. `roccoengine.com`: 10.46 to 12.08 the first year, 10.46 to 12.03 to renew
   (Namecheap renews at 19.98).
3. `roccoengine.org`: 7.98 to 9.99 the first year, 10.99 to 11.84 to renew.
4. `rocco.games`: short and on-theme, 8.24 to 14.99 the first year, 26.20 to
   31.00 to renew.

Avoid `rocco.page` and `rocco.fun` (premium), `rocco.game` (about 350 per
year), `rocco.codes` and `rocco.engineering` (renewal above 60). The short
names `rocco.dev`, `rocco.gg`, `rocco.sh`, `rocco.io` and `rocco.app` are
taken.

Prices change. Check the exact name at the registrar before purchase.

[iana-rdap]: https://data.iana.org/rdap/dns.json
[iana-tlds]: https://data.iana.org/TLD/tlds-alpha-by-domain.txt
[cf-tld]: https://www.cloudflare.com/tld-policies/
[costgoat]: https://costgoat.com/pricing/cloudflare-domains
[do-nc-dev]: https://domainoffer.net/tld/dev/namecheap
[rtomayko]: https://github.com/rtomayko/rocco
[crate]: https://crates.io/crates/rocco
[npm]: https://registry.npmjs.org/rocco
[pypi]: https://pypi.org/project/rocco/
[seasons]: https://store.steampowered.com/app/2700510
[island]: https://store.steampowered.com/app/1394480/Roccos_Island_Ring_to_End_the_Pain/
[moby]: https://www.mobygames.com/game/rocco
[a11ce]: https://github.com/a11ce/roc
[amber]: https://github.com/bsgbryan/Amber
