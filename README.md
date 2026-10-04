logo > https://github.com/user-attachments/assets/f46e13f2-fcd7-4bfb-90f5-09f3f91fcfe6 



# blue-star

A menu-driven OSINT tool written in Bash. Everything runs from one script,
no Python, no pip. Needs `curl` to work, and a few optional tools for the
full experience.

Coded by [shcrypta27](https://github.com/shcrypta27).

<img width="1696" height="935" alt="image" src="https://github.com/user-attachments/assets/95e3477b-c669-4659-9bc7-da50119359b3" />


## What's in it

Nine scans, picked from a numbered menu:

- **IP scan** — whois, geolocation, reverse DNS
- **Domain scan** — whois, DNS records, subdomains from crt.sh
- **Username search** — checks a handle against 210+ sites
- **Email scan** — MX records, SPF/DMARC, gravatar
- **Phone scan** — country code lookup + manual search links
- **WHOIS** — raw whois output for any domain or IP
- **Dork builder** — 15 google dorks per domain
- **Port check** — 24 common TCP ports
- **Stealth mode** — routes through Tor, rotates user agents, adds delay

You can also call any scan directly from the terminal with a flag, which is
handy if you want to pipe the output somewhere.

---

## Install

### Debian / Ubuntu / Kali

```bash
sudo apt update
sudo apt install curl whois dnsutils tor
git clone https://github.com/shcrypta27/osint-blue-star.git
cd osint-blue-star
chmod +x bluestar.sh
./bluestar.sh
```

### Arch / Manjaro

```bash
sudo pacman -S curl whois bind tor git
git clone https://github.com/shcrypta27/osint-blue-star.git
cd osint-blue-star
chmod +x bluestar.sh
./bluestar.sh
```

### Fedora / RHEL

```bash
sudo dnf install curl whois bind-utils tor git
git clone https://github.com/shcrypta27/osint-blue-star.git
cd osint-blue-star
chmod +x bluestar.sh
./bluestar.sh
```

### macOS

```bash
brew install curl whois tor git
git clone https://github.com/shcrypta27/osint-blue-star.git
cd osint-blue-star
chmod +x bluestar.sh
./bluestar.sh
```

### Termux (Android)

```bash
pkg update
pkg install curl whois dnsutils tor git
git clone https://github.com/shcrypta27/osint-blue-star.git
cd osint-blue-star
chmod +x bluestar.sh
./bluestar.sh
```

### Windows — WSL (recommended)

Install WSL with Ubuntu from the Microsoft Store, then inside the Ubuntu shell:

```bash
sudo apt update
sudo apt install curl whois dnsutils tor git
git clone https://github.com/shcrypta27/osint-blue-star.git
cd osint-blue-star
chmod +x bluestar.sh
./bluestar.sh
```

### Windows — Git Bash

Git Bash can run the script, but `whois`, `dig`, and Tor aren't included.
Best to use WSL instead. If you want to try anyway:

```bash
git clone https://github.com/shcrypta27/osint-blue-star.git
cd osint-blue-star
./bluestar.sh
```

Some scans will report missing tools.

---

## Usage

Interactive menu:

```bash
./bluestar.sh
```

Direct scan:

```bash
./bluestar.sh -1    # ip address
./bluestar.sh -2    # domain
./bluestar.sh -3    # username
./bluestar.sh -4    # email
./bluestar.sh -5    # phone number
./bluestar.sh -6    # whois
./bluestar.sh -7    # google dorks
./bluestar.sh -8    # port check
./bluestar.sh -9    # launch menu in stealth mode
./bluestar.sh -help
```

Because the CLI reads the target from stdin, you can pipe:

```bash
echo "example.com" | ./bluestar.sh -2 > results.txt
```

## Stealth mode

Option `[9]` in the menu. What it actually changes:

- sends every HTTP request through Tor if Tor is running on `127.0.0.1:9050`
- picks a random user agent from a pool of real browser signatures
- adds browser-like headers so requests don't look scripted
- waits a random 0.4–2.0 seconds between requests
- runs the username scan one site at a time, in shuffled order

Start Tor before using it:

```bash
sudo systemctl start tor
```

If Tor isn't running, stealth still works — just without the Tor layer.

Adjust the delay if you want to go slower:

```bash
BS_JITTER_MIN=1.0 BS_JITTER_MAX=3.0 ./bluestar.sh -9
```

The username scan in stealth mode takes several minutes because it goes site
by site with a delay between each one. That's on purpose.

## Note

Only use this on systems you own or have permission to test. Scanning
systems without permission is illegal in most countries.

## Legal

- [LICENSE.md](LICENSE.md) — usage terms (proprietary, permission required)
- [DISCLAIMER.md](DISCLAIMER.md) — authorised use only

## Feedback

If you find a bug, a site that's listed wrong in the username scan, or
something that just doesn't work on your system, let me know. Same goes the
other way — if you've got a tip, a cleaner way to do something, or a tool
worth adding, open an issue or send a PR. I'd rather hear about it than not.
