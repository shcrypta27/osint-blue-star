#!/usr/bin/env bash
# =============================================================================
#   blue-star · lightweight OSINT toolkit
#   coded by shcrypta27 — https://github.com/shcrypta27
#
#   For authorised security research / educational use only.
#   Only query targets you own or have explicit permission to test.
#
#   ── CLI USAGE ─────────────────────────────────────────────────────────────
#     bash ./bluestar.sh          interactive menu
#     bash ./bluestar.sh -1       IP Address Scan
#     bash ./bluestar.sh -2       Domain Scan
#     bash ./bluestar.sh -3       Username Search
#     bash ./bluestar.sh -4       Email Scan
#     bash ./bluestar.sh -5       Phone Number Scan
#     bash ./bluestar.sh -6       WHOIS Lookup
#     bash ./bluestar.sh -7       Google Dork Builder
#     bash ./bluestar.sh -8       Common Port Check
#     bash ./bluestar.sh -9       enter menu in stealth mode
#     bash ./bluestar.sh -help    show help
#
#   ── STEALTH MODE ──────────────────────────────────────────────────────────
#   Selecting [9] "Stealth" from the main menu re-runs the entire toolkit in a
#   hardened operational mode:
#     · All HTTP(S) traffic is routed through Tor (127.0.0.1:9050) when present
#     · Requests are jittered (random delay) instead of fired back-to-back
#     · User-Agent is rotated from a pool of real browser signatures
#     · Additional browser-like headers are attached to reduce fingerprinting
#     · Username scan becomes sequential + shuffled (no parallel burst)
#     · Palette switches to greyscale
#   This reduces fingerprinting and rate-limit exposure. It is NOT a guarantee
#   of anonymity: DNS, timing, and content signatures can still leak. Tor is
#   the only real anonymity layer here — start it before entering stealth mode
#   (sudo systemctl start tor).
# =============================================================================

set -uo pipefail

# ── global mode flags ────────────────────────────────────────────────────────
STEALTH=0
TOR_AVAILABLE=0
CLI_MODE=0

# ── palette (reassigned by apply_palette based on $STEALTH) ──────────────────
BLUE='' CYAN='' GREEN='' RED='' YELLOW='' DIM='' BOLD='' NC='' NUMCOL=''

apply_palette() {
    if (( STEALTH )); then
        # greyscale palette
        BLUE=$'\033[1;90m'              # frame — bold dark grey
        CYAN=$'\033[0;37m'              # prompts — light grey
        GREEN=$'\033[1;97m'             # positives — bright white
        RED=$'\033[0;90m'               # negatives — dark grey
        YELLOW=$'\033[0;37m'            # headers — light grey
        DIM=$'\033[2;90m'               # notes — dim dark grey
        BOLD=$'\033[1;37m'              # bold — white
        NUMCOL=$'\033[1;37m'            # menu numbers — white
    else
        # blue palette (normal)
        BLUE=$'\033[1;34m'
        CYAN=$'\033[1;36m'
        GREEN=$'\033[1;32m'
        RED=$'\033[1;31m'
        YELLOW=$'\033[1;33m'
        DIM=$'\033[2m'
        BOLD=$'\033[1m'
        NUMCOL=$'\033[38;5;214m'        # amber / yellow-orange
    fi
    NC=$'\033[0m'
}

# ── user-agent pool (real browser signatures) ────────────────────────────────
UA_POOL=(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:123.0) Gecko/20100101 Firefox/123.0"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:122.0) Gecko/20100101 Firefox/122.0"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3 Safari/605.1.15"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3 Safari/605.1.15"
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    "Mozilla/5.0 (X11; Linux x86_64; rv:123.0) Gecko/20100101 Firefox/123.0"
    "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:122.0) Gecko/20100101 Firefox/122.0"
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3 Mobile/15E148 Safari/604.1"
    "Mozilla/5.0 (iPad; CPU OS 17_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3 Mobile/15E148 Safari/604.1"
    "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36"
    "Mozilla/5.0 (Linux; Android 13; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36"
)

UA="${UA_POOL[0]}"

# ── helpers ──────────────────────────────────────────────────────────────────
have()  { command -v "$1" >/dev/null 2>&1; }
title() { printf '\n%s┌─[%s %s%s%s %s]%s\n' "$BLUE" "$NC" "$BOLD" "$1" "$NC" "$BLUE" "$NC"; }
row()   { printf '  %s%-14s%s %s\n' "$BOLD" "$1:" "$NC" "$2"; }
note()  { printf '  %s%s%s\n' "$DIM" "$1" "$NC"; }

pause() {
    if (( CLI_MODE )); then
        printf '\n'
        return
    fi
    printf '\n%s  press [enter] to return to the menu…%s' "$DIM" "$NC"
    read -r _
}

dns_query() {
    local type="$1" name="$2"
    if have dig; then
        dig +short "$type" "$name" 2>/dev/null
    elif have host; then
        host -t "$type" "$name" 2>/dev/null | sed 's/^[^ ]* //'
    elif have nslookup; then
        nslookup -type="$type" "$name" 2>/dev/null | tail -n +3
    else
        printf '  (dig / host / nslookup not installed)\n'
    fi
}

md5_of() {
    if have md5sum;    then printf '%s' "$1" | md5sum | awk '{print $1}'
    elif have md5;     then printf '%s' "$1" | md5 -q
    elif have openssl; then printf '%s' "$1" | openssl md5 | awk '{print $2}'
    else printf 'unavailable'; fi
}

clean_domain() {
    local d="$1"
    d="${d#http://}"; d="${d#https://}"; d="${d%%/*}"; d="${d%%\?*}"
    printf '%s' "$d"
}

# ── HTTP layer (mode-aware) ──────────────────────────────────────────────────
_jitter() {
    local min="${BS_JITTER_MIN:-0.4}"
    local max="${BS_JITTER_MAX:-2.0}"
    awk -v a="$min" -v b="$max" 'BEGIN{srand(); printf "%.2f", a+rand()*(b-a)}'
}

http_get() {
    local url="$1"; shift
    if (( STEALTH )); then
        local ua="${UA_POOL[$((RANDOM % ${#UA_POOL[@]}))]}"
        sleep "$(_jitter)"
        local args=(-sL --max-time 30 --compressed
            -A "$ua"
            -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8'
            -H 'Accept-Language: en-US,en;q=0.5'
            -H 'DNT: 1'
            -H 'Upgrade-Insecure-Requests: 1'
            -H 'Sec-Fetch-Dest: document'
            -H 'Sec-Fetch-Mode: navigate'
            -H 'Sec-Fetch-Site: none'
            -H 'Sec-Fetch-User: ?1'
        )
        (( TOR_AVAILABLE )) && args+=(--socks5-hostname 127.0.0.1:9050)
        curl "${args[@]}" "$@" "$url"
    else
        curl -sL --max-time 15 -A "$UA" "$@" "$url"
    fi
}

http_code() {
    local url="$1"
    if (( STEALTH )); then
        local ua="${UA_POOL[$((RANDOM % ${#UA_POOL[@]}))]}"
        sleep "$(_jitter)"
        local args=(-s -o /dev/null -w '%{http_code}' -L --max-time 25 --compressed
            -A "$ua"
            -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
            -H 'Accept-Language: en-US,en;q=0.5'
            -H 'DNT: 1'
        )
        (( TOR_AVAILABLE )) && args+=(--socks5-hostname 127.0.0.1:9050)
        curl "${args[@]}" "$url"
    else
        curl -s -o /dev/null -w '%{http_code}' -L --max-time 12 -A "$UA" "$url"
    fi
}

# ── Tor detection ────────────────────────coded by shcrypta27────────────────────────────────────
check_tor() {
    printf '\n  %schecking for Tor SOCKS5 on 127.0.0.1:9050 …%s\n' "$DIM" "$NC"
    local out
    out=$(curl -s --max-time 8 --socks5-hostname 127.0.0.1:9050 \
        "https://check.torproject.org/api/ip" 2>/dev/null)
    if printf '%s' "$out" | grep -q '"IsTor":true'; then
        TOR_AVAILABLE=1
        local ip
        ip=$(printf '%s' "$out" | grep -o '"IP":"[^"]*"' | cut -d'"' -f4)
        printf '  %s[✓]%s Tor is active  ·  exit node %s\n' "$GREEN" "$NC" "$ip"
        printf '  %s    all HTTP(S) requests will be routed through Tor%s\n' "$DIM" "$NC"
    else
        TOR_AVAILABLE=0
        printf '  %s[!]%s Tor not detected on 127.0.0.1:9050\n' "$YELLOW" "$NC"
        printf '  %s    stealth will run with UA rotation + jitter + sequential only%s\n' "$DIM" "$NC"
        printf '  %s    for real anonymity start Tor first:  sudo systemctl start tor%s\n' "$DIM" "$NC"
    fi
    (( CLI_MODE )) || sleep 2
}

# ── banner ───────────────────────────────────────────────────────────────────
banner() {
    clear 2>/dev/null || printf '\033[2J\033[H'
    printf '%s' "$BLUE"
    cat <<'ASCII'

      __________   _____        _____ _____  ___________            ___________  __________   _________   __________                    .       .                            
     │     .    \ │     |      │     │     ││           │         /    ________|│          │ /         \ │     .    \                        .  |  .                               
     :     |     ::     |      :     :     ::    ----.--:        (_____     \  ::---    ---::    _      ::     |     :                        \ | /    +                  
     :     .    <       │-----.                  ____|--.        :     │     '_::  |    |  :      │      :     .    <                 *        \|/                  
     |     |     ..           :.           ..           :              │     .  :__|    |__:.     |     .|     |     .                    --==> * <==--   '                               
     |__________/:|___________||___________||___________|        |\_________/|     |____:   |_____|_____||_____|_____|                   +     /|\   .                                
     :         : ::           ::           ::           :        : :       : :     :    :   :     :     ::     :     :                        / | \                            
     :_________:/ :___________::___________::___________:         \:_______:/      :____:   :_____:_____::_____:_____:                .      '  |  '       *                   
                                                                                                                                                |
                                                                                                                                          .     '    .
                                                                                                                                                                     
                                                                                                                                                                     
                                                                                                                                                                     
ASCII
    printf '%s' "$NC"
    printf '            %s★%s  %sblue-star%s %sv1.0%s  %s★%s\n' \
        "$BLUE" "$NC" "$BOLD" "$NC" "$DIM" "$NC" "$BLUE" "$NC"
    printf '     %s────────────────────────────────────────────────%s\n' "$BLUE" "$NC"
    printf '            coded by %sshcrypta27%s\n' "$CYAN" "$NC"
    printf '     %shttps://github.com/shcrypta27%s\n' "$DIM" "$NC"
    printf '     %s────────────────────────────────────────────────%s\n' "$BLUE" "$NC"
}

# ── menu ─────────────────────────────────────────────────────────────────────
menu() {
    printf '\n  %s──[ SELECT A MODULE ]──────────────────────────────%s\n\n' "$BLUE" "$NC"
    printf '   %s[1]%s   IP Address Scan\n'           "$NUMCOL" "$NC"
    printf '   %s[2]%s   Domain Scan\n'               "$NUMCOL" "$NC"
    printf '   %s[3]%s   Username Search  %s(210+ sites)%s\n' "$NUMCOL" "$NC" "$DIM" "$NC"
    printf '   %s[4]%s   Email Scan\n'                "$NUMCOL" "$NC"
    printf '   %s[5]%s   Phone Number Scan\n'         "$NUMCOL" "$NC"
    printf '   %s[6]%s   WHOIS Lookup\n'              "$NUMCOL" "$NC"
    printf '   %s[7]%s   Google Dork Builder\n'       "$NUMCOL" "$NC"
    printf '   %s[8]%s   Common Port Check\n'         "$NUMCOL" "$NC"
    if (( STEALTH )); then
        printf '   %s[9]%s   Exit Stealth Mode\n'     "$NUMCOL" "$NC"
    else
        printf '   %s[9]%s   Stealth Mode\n'          "$NUMCOL" "$NC"
    fi
    printf '   %s[0]%s   Exit\n'                      "$NUMCOL" "$NC"
    printf '\n  %s──[ 0-9 ]────────────────────────────────────────%s\n' "$BLUE" "$NC"
    printf '\n  %sblue-star ❯%s ' "$BLUE" "$NC"
}

# =============================================================================
#  1 · IP ADDRESS SCAN
# =============================================================================
fn_ip() {
    printf '\n%sIP address or hostname:%s ' "$CYAN" "$NC"
    read -r target
    [[ -z "$target" ]] && return
    title "IP SCAN: $target"

    if have whois; then
        printf '\n%s[ whois ]%s\n' "$YELLOW" "$NC"
        local w
        w=$(whois "$target" 2>/dev/null | grep -Ei \
            '^[[:space:]]*(netname|orgname|org-name|organisation|country|inetnum|netrange|route|origin|descr|abuse-mailbox|cidr|address)' \
            | head -20)
        [[ -z "$w" ]] && w=$(whois "$target" 2>/dev/null | head -20)
        printf '%s\n' "${w:-  (no whois data)}" | sed 's/^/  /'
    else
        note "whois not installed — skipped"
    fi

    printf '\n%s[ geolocation · ip-api.com ]%s\n' "$YELLOW" "$NC"
    local json status
    json=$(http_get "http://ip-api.com/json/${target}?fields=status,message,country,countryCode,regionName,city,zip,lat,lon,timezone,isp,org,as,reverse,mobile,proxy,hosting,query" 2>/dev/null)
    status=$(printf '%s' "$json" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

    if [[ "$status" == "success" ]]; then
        local key val
        for key in query country countryCode regionName city zip lat lon timezone isp org as reverse mobile proxy hosting; do
            val=$(printf '%s' "$json" | grep -o "\"$key\":\"[^\"]*\"" | cut -d'"' -f4)
            [[ -z "$val" ]] && val=$(printf '%s' "$json" | grep -o "\"$key\":[^,}]*" | head -1 | cut -d: -f2 | tr -d ' ')
            [[ -n "$val" && "$val" != "false" && "$val" != "null" ]] && row "$key" "$val"
        done
    else
        note "lookup failed or rate-limited"
    fi

    printf '\n%s[ reverse dns ]%s\n' "$YELLOW" "$NC"
    dns_query PTR "$target" | sed 's/^/  /'
    [[ -z "$(dns_query PTR "$target")" ]] && note "no PTR record"
    pause
}

# =============================================================================
#  2 · DOMAIN SCAN
# =============================================================================
fn_domain() {
    printf '\n%sDomain (e.g. example.com):%s ' "$CYAN" "$NC"
    read -r raw
    [[ -z "$raw" ]] && return
    local dom; dom=$(clean_domain "$raw")
    title "DOMAIN SCAN: $dom"

    printf '\n%s[ whois ]%s\n' "$YELLOW" "$NC"
    if have whois; then
        local w
        w=$(whois "$dom" 2>/dev/null | grep -Ei \
            '^[[:space:]]*(domain name|registrar:|registrant|creation date|created|updated date|expiry|expiration|name server|status|org|country)' \
            | head -25)
        [[ -z "$w" ]] && w=$(whois "$dom" 2>/dev/null | head -25)
        printf '%s\n' "${w:-  (no whois data)}" | sed 's/^/  /'
    else
        note "whois not installed — skipped"
    fi

    printf '\n%s[ dns records ]%s\n' "$YELLOW" "$NC"
    local t out
    for t in A AAAA MX NS TXT; do
        out=$(dns_query "$t" "$dom" | head -6)
        if [[ -n "$out" ]]; then
            printf '  %s%s%s\n' "$BOLD" "$t" "$NC"
            printf '%s\n' "$out" | sed 's/^/    /'
        fi
    done

    printf '\n%s[ subdomains · crt.sh ]%s\n' "$YELLOW" "$NC"
    local subs
    subs=$(http_get "https://crt.sh/?q=%25.${dom}&output=json" 2>/dev/null \
           | grep -o '"name_value":"[^"]*"' | cut -d'"' -f4 \
           | sed 's/\*\.//g' | sort -u | head -40)
    if [[ -z "$subs" ]]; then
        note "no results (or crt.sh unreachable)"
    else
        printf '%s\n' "$subs" | sed 's/^/  /'
        printf '\n'
        note "$(printf '%s\n' "$subs" | wc -l) unique names (max 40 shown)"
    fi
    pause
}

# =============================================================================
#  3 · USERNAME SEARCH  —  210+ platforms         coded by shcrypta27
# =============================================================================
USERNAME_SITES=(
    # ── social ───────────────────────────────────────────────────────────────
    "X (Twitter)|https://x.com/%s"
    "Twitter|https://twitter.com/%s"
    "Facebook|https://www.facebook.com/%s"
    "Instagram|https://www.instagram.com/%s/"
    "Reddit|https://www.reddit.com/user/%s/about.json"
    "Tumblr|https://%s.tumblr.com"
    "Pinterest|https://www.pinterest.com/%s/"
    "LinkedIn|https://www.linkedin.com/in/%s"
    "TikTok|https://www.tiktok.com/@%s"
    "Snapchat|https://www.snapchat.com/add/%s"
    "Mastodon.social|https://mastodon.social/@%s"
    "VK|https://vk.com/%s"
    "Odnoklassniki|https://ok.ru/%s"
    "Weibo|https://weibo.com/%s"
    "Threads|https://www.threads.net/@%s"
    "Bluesky|https://bsky.app/profile/%s.bsky.social"
    "Counter.Social|https://counter.social/@%s"
    "Minds|https://www.minds.com/%s/"
    "Gab|https://gab.com/%s"
    "Parler|https://parler.com/%s"
    "MeWe|https://mewe.com/i/%s"
    "Vero|https://vero.co/%s"
    "Pillowfort|https://www.pillowfort.social/%s"

    # ── blogging / writing ───────────────────────────────────────────────────
    "Dreamwidth|https://%s.dreamwidth.org"
    "LiveJournal|https://%s.livejournal.com"
    "Blogspot|https://%s.blogspot.com"
    "WordPress|https://%s.wordpress.com"
    "Medium|https://medium.com/@%s"
    "Substack|https://%s.substack.com"
    "Ghost|https://%s.ghost.io"
    "Write.as|https://write.as/%s"
    "Bear Blog|https://%s.bearblog.dev"
    "Vocal|https://vocal.media/authors/%s"
    "Hashnode|https://hashnode.com/@%s"
    "Dev.to|https://dev.to/%s"
    "HackerNoon|https://hackernoon.com/u/%s"
    "Tealfeed|https://tealfeed.com/%s"
    "Daily.dev|https://app.daily.dev/%s"
    "Product Hunt|https://www.producthunt.com/@%s"
    "Indie Hackers|https://www.indiehackers.com/%s"
    "Betalist|https://betalist.com/@%s"

    # ── dev / code hosting ───────────────────────────────────────────────────
    "GitHub|https://github.com/%s"
    "GitLab|https://gitlab.com/%s"
    "Bitbucket|https://bitbucket.org/%s/"
    "SourceForge|https://sourceforge.net/u/%s/profile"
    "Codeberg|https://codeberg.org/%s"
    "Gitea|https://gitea.com/%s"
    "Gitee|https://gitee.com/%s"
    "Launchpad|https://launchpad.net/~%s"
    "Replit|https://replit.com/@%s"
    "CodePen|https://codepen.io/%s"
    "JSFiddle|https://jsfiddle.net/user/%s"
    "Glitch|https://glitch.com/@%s"
    "Stack Overflow|https://stackoverflow.com/users/filter?search=%s"
    "HackerNews|https://news.ycombinator.com/user?id=%s"
    "HackerRank|https://www.hackerrank.com/%s"
    "LeetCode|https://leetcode.com/%s/"
    "Codeforces|https://codeforces.com/profile/%s"
    "CodeChef|https://www.codechef.com/users/%s"
    "TopCoder|https://www.topcoder.com/members/%s"
    "Kaggle|https://www.kaggle.com/%s"
    "HackerEarth|https://www.hackerearth.com/@%s"

    # ── security / bug bounty ────────────────────────────────────────────────
    "TryHackMe|https://tryhackme.com/p/%s"
    "HackTheBox|https://app.hackthebox.com/users/%s"
    "Root-me|https://www.root-me.org/%s"
    "Bugcrowd|https://bugcrowd.com/%s"
    "HackerOne|https://hackerone.com/%s"
    "Intigriti|https://app.intigriti.com/profile/%s"
    "YesWeHack|https://yeswehack.com/hunters/%s"

    # ── package registries ───────────────────────────────────────────────────
    "npm|https://www.npmjs.com/~%s"
    "PyPI|https://pypi.org/user/%s/"
    "RubyGems|https://rubygems.org/profiles/%s"
    "Packagist|https://packagist.org/users/%s/"
    "NuGet|https://www.nuget.org/profiles/%s"
    "Crates.io|https://crates.io/users/%s"
    "Docker Hub|https://hub.docker.com/u/%s"
    "Hex.pm|https://hex.pm/users/%s"
    "Pub.dev|https://pub.dev/publishers/%s"
    "CocoaPods|https://cocoapods.org/owners/%s"

    # ── gaming / streaming ───────────────────────────────────────────────────
    "Steam|https://steamcommunity.com/id/%s"
    "Xbox|https://xboxgamertag.com/search/%s"
    "PSN|https://psnprofiles.com/%s"
    "Fortnite Tracker|https://fortnitetracker.com/profile/all/%s"
    "Twitch|https://www.twitch.tv/%s"
    "YouTube|https://www.youtube.com/@%s"
    "Kick|https://kick.com/%s"
    "DLive|https://dlive.tv/%s"
    "Trovo|https://trovo.live/s/%s"
    "Rumble|https://rumble.com/user/%s"
    "Odysee|https://odysee.com/@%s"
    "BitChute|https://www.bitchute.com/channel/%s/"
    "Dailymotion|https://www.dailymotion.com/%s"
    "Vimeo|https://vimeo.com/%s"
    "Metacafe|https://www.metacafe.com/%s"
    "Roblox|https://www.roblox.com/user.aspx?username=%s"
    "Chess.com|https://www.chess.com/member/%s"
    "Lichess|https://lichess.org/@/%s"
    "Faceit|https://www.faceit.com/en/players/%s"
    "ESL Play|https://play.eslgaming.com/player/%s"

    # ── music / audio ────────────────────────────────────────────────────────
    "SoundCloud|https://soundcloud.com/%s"
    "Spotify|https://open.spotify.com/user/%s"
    "Bandcamp|https://bandcamp.com/%s"
    "Mixcloud|https://www.mixcloud.com/%s/"
    "Audius|https://audius.co/%s"
    "Last.fm|https://www.last.fm/user/%s"
    "Discogs|https://www.discogs.com/user/%s"
    "Genius|https://genius.com/%s"
    "ReverbNation|https://www.reverbnation.com/%s"
    "Audiomack|https://audiomack.com/%s"

    # ── photography / art ────────────────────────────────────────────────────
    "Flickr|https://www.flickr.com/people/%s"
    "500px|https://500px.com/p/%s"
    "DeviantArt|https://www.deviantart.com/%s"
    "ArtStation|https://www.artstation.com/%s"
    "Behance|https://www.behance.net/%s"
    "Dribbble|https://dribbble.com/%s"
    "Unsplash|https://unsplash.com/@%s"
    "Pexels|https://www.pexels.com/@%s"
    "Pixabay|https://pixabay.com/users/%s"
    "Imgur|https://imgur.com/user/%s"
    "Giphy|https://giphy.com/%s"
    "Tenor|https://tenor.com/users/%s"
    "VSCO|https://vsco.co/%s/gallery"
    "EyeEm|https://www.eyeem.com/u/%s"
    "YouPic|https://%s.youpic.com"

    # ── dating / meetup ──────────────────────────────────────────────────────
    "Badoo|https://badoo.com/en/%s"
    "OkCupid|https://www.okcupid.com/profile/%s"
    "POF|https://www.pof.com/viewprofile.aspx?profile_id=%s"
    "Tagged|https://www.tagged.com/%s"
    "MeetMe|https://www.meetme.com/%s"

    # ── professional / link-in-bio ───────────────────────────────────────────
    "Wellfound|https://wellfound.com/u/%s"
    "Crunchbase|https://www.crunchbase.com/person/%s"
    "About.me|https://about.me/%s"
    "Gravatar|https://gravatar.com/%s"
    "Keybase|https://keybase.io/%s"
    "Linktree|https://linktr.ee/%s"
    "Carrd|https://%s.carrd.co"
    "Bio.link|https://bio.link/%s"
    "Beacons|https://beacons.ai/%s"
    "AllMyLinks|https://allmylinks.com/%s"
    "Bento|https://bento.me/%s"

    # ── forums / community ───────────────────────────────────────────────────
    "Quora|https://www.quora.com/profile/%s"
    "Disqus|https://disqus.com/by/%s/"
    "Something Awful|https://forums.somethingawful.com/member.php?username=%s"
    "ResetEra|https://www.resetera.com/members/?username=%s"
    "NeoGAF|https://www.neogaf.com/members/?username=%s"
    "BlackHatWorld|https://www.blackhatworld.com/members/?username=%s"
    "Digg|https://digg.com/@%s"
    "Slashdot|https://slashdot.org/~%s"
    "Metafilter|https://www.metafilter.com/user/%s"
    "Lobste.rs|https://lobste.rs/~%s"

    # ── shopping / marketplaces ──────────────────────────────────────────────
    "eBay|https://www.ebay.com/usr/%s"
    "Etsy|https://www.etsy.com/shop/%s"
    "Fiverr|https://www.fiverr.com/%s"
    "Upwork|https://www.upwork.com/freelancers/~%s"
    "Freelancer|https://www.freelancer.com/u/%s"
    "PeoplePerHour|https://www.peopleperhour.com/freelancer/%s"
    "Gumroad|https://%s.gumroad.com"
    "Ko-fi|https://ko-fi.com/%s"
    "Patreon|https://www.patreon.com/%s"
    "Buy Me a Coffee|https://www.buymeacoffee.com/%s"
    "Poshmark|https://poshmark.com/closet/%s"
    "Depop|https://www.depop.com/%s/"
    "Vinted|https://www.vinted.com/member/%s"
    "Mercari|https://www.mercari.com/u/%s"
    "Reverb|https://reverb.com/shop/%s"

    # ── education / learning ─────────────────────────────────────────────────
    "Coursera|https://www.coursera.org/user/%s"
    "Udemy|https://www.udemy.com/user/%s/"
    "Skillshare|https://www.skillshare.com/profile/%s"
    "Duolingo|https://www.duolingo.com/profile/%s"
    "Codecademy|https://www.codecademy.com/profiles/%s"
    "FreeCodeCamp|https://www.freecodecamp.org/%s"
    "Pluralsight|https://app.pluralsight.com/profile/%s"

    # ── finance / payments ───────────────────────────────────────────────────
    "Cash App|https://cash.app/\$%s"
    "Venmo|https://venmo.com/u/%s"
    "PayPal.me|https://www.paypal.com/paypalme/%s"
    "Revolut|https://revolut.me/%s"
    "Wise|https://wise.com/pay/me/%s"
    "Coinbase|https://www.coinbase.com/%s"
    "Binance|https://www.binance.com/en/profile/%s"

    # ── crypto / web3 ────────────────────────────────────────────────────────
    "OpenSea|https://opensea.io/%s"
    "Rarible|https://rarible.com/%s"
    "Foundation|https://foundation.app/@%s"
    "SuperRare|https://superrare.com/%s"
    "Etherscan|https://etherscan.io/address/%s"
    "BitcoinTalk|https://bitcointalk.org/index.php?action=profile;u=%s"
    "Hive|https://hive.blog/@%s"
    "Steemit|https://steemit.com/@%s"

    # ── other social / ask-me ────────────────────────────────────────────────
    "Clubhouse|https://www.clubhouse.com/@%s"
    "Yubo|https://yubo.live/%s"
    "Ask.fm|https://ask.fm/%s"
    "CuriousCat|https://curiouscat.live/%s"
    "Tellonym|https://tellonym.me/%s"

    # ── books / film / anime ─────────────────────────────────────────────────
    "Goodreads|https://www.goodreads.com/%s"
    "Letterboxd|https://letterboxd.com/%s/"
    "Trakt|https://trakt.tv/users/%s"
    "MyAnimeList|https://myanimelist.net/profile/%s"
    "AniList|https://anilist.co/user/%s"
    "Backloggd|https://backloggd.com/u/%s"
    "Wattpad|https://www.wattpad.com/user/%s"
    "FanFiction|https://www.fanfiction.net/u/%s"
    "Archive of Our Own|https://archiveofourown.org/users/%s"
    "Royal Road|https://www.royalroad.com/profile/%s"
    "BookBub|https://www.bookbub.com/profile/%s"
    "LibraryThing|https://www.librarything.com/profile/%s"

    # ── fitness / lifestyle ──────────────────────────────────────────────────
    "Strava|https://www.strava.com/athletes/%s"
    "Runkeeper|https://runkeeper.com/user/%s"
    "Fitbit|https://www.fitbit.com/user/%s"
    "MyFitnessPal|https://www.myfitnesspal.com/profile/%s"
    "Untappd|https://untappd.com/user/%s"
    "Vivino|https://www.vivino.com/users/%s"

    # ── travel / hospitality ─────────────────────────────────────────────────
    "TripAdvisor|https://www.tripadvisor.com/members/%s"
    "Couchsurfing|https://www.couchsurfing.com/people/%s"
    "Warmshowers|https://www.warmshowers.org/users/%s"

    # ── productivity / misc ──────────────────────────────────────────────────
    "Notion|https://www.notion.so/%s"
    "Trello|https://trello.com/%s"
    "Asana|https://app.asana.com/%s"
)

check_site() {
    local entry="$1" user="$2" tmp="$3"
    local name="${entry%%|*}"
    local url="${entry#*|}"
    url="${url//%s/$user}"

    local code
    code=$(http_code "$url")

    local out
    case "$code" in
        200|201|202)
            out=$(printf '\002  %s[+] FOUND%s     %-20s %s%s%s' "$GREEN" "$NC" "$name" "$DIM" "$url" "$NC") ;;
        404|410)
            out=$(printf '\003  %s[-] not found%s %-20s %s%s%s' "$DIM" "$NC" "$name" "$DIM" "$url" "$NC") ;;
        401|403)
            out=$(printf '\001  %s[?] blocked%s   %-20s %s%s%s' "$YELLOW" "$NC" "$name" "$DIM" "$url" "$NC") ;;
        429)
            out=$(printf '\001  %s[?] rate-l.%s  %-20s %s%s%s' "$YELLOW" "$NC" "$name" "$DIM" "$url" "$NC") ;;
        *)
            out=$(printf '\001  %s[?] %-7s%s %-20s %s%s%s' "$YELLOW" "$code" "$NC" "$name" "$DIM" "$url" "$NC") ;;
    esac
    printf '%s\n' "$out" >> "$tmp"
}

_shuffle_indices() {
    local n=$1 i j t
    local -a idx=()
    for ((i=0; i<n; i++)); do idx[i]=$i; done
    for ((i=n-1; i>0; i--)); do
        j=$((RANDOM % (i+1)))
        t=${idx[i]}; idx[i]=${idx[j]}; idx[j]=$t
    done
    printf '%s\n' "${idx[@]}"
}

fn_username() {
    printf '\n%sUsername / handle:%s ' "$CYAN" "$NC"
    read -r user
    [[ -z "$user" ]] && return
    user="${user#@}"
    [[ -z "$user" ]] && return

    title "USERNAME SEARCH: $user"

    local tmp; tmp=$(mktemp)
    local total="${#USERNAME_SITES[@]}"

    if (( STEALTH )); then
        note "stealth: sequential + shuffled + jitter — this will take several minutes"
        (( TOR_AVAILABLE )) && note "routing through Tor — expect additional latency" || note "no Tor — UA rotation + jitter only"
        printf '  progress: '
        local i
        while IFS= read -r i; do
            check_site "${USERNAME_SITES[$i]}" "$user" "$tmp"
            printf '.'
        done < <(_shuffle_indices "$total")
        printf '\n'
    else
        note "scanning ${total} platforms · 15 concurrent workers · timeouts 10s"
        note "403/429 responses usually mean the platform blocked the check, not that the account is absent"
        printf '\n  scanning'

        local max_jobs=15 entry
        for entry in "${USERNAME_SITES[@]}"; do
            while (( $(jobs -r | wc -l) >= max_jobs )); do sleep 0.05; done
            check_site "$entry" "$user" "$tmp" &
        done
        wait
        printf '\r\033[K'
    fi

    local found blocked missing
    found=$(grep -c $'^\002' "$tmp" 2>/dev/null);   found=${found:-0}
    blocked=$(grep -c $'^\001' "$tmp" 2>/dev/null); blocked=${blocked:-0}
    missing=$(grep -c $'^\003' "$tmp" 2>/dev/null); missing=${missing:-0}

    printf '\n%s── FOUND (%s) ─────────────────────────────────────%s\n\n' "$GREEN" "$found" "$NC"
    grep $'^\002' "$tmp" 2>/dev/null | sed $'s/^\002//' || true

    printf '\n%s── BLOCKED / UNKNOWN (%s) ─────────────────────────%s\n\n' "$YELLOW" "$blocked" "$NC"
    grep $'^\001' "$tmp" 2>/dev/null | sed $'s/^\001//' || true

    printf '\n%s── NOT FOUND (%s) ─────────────────────────────────%s\n\n' "$DIM" "$missing" "$NC"
    grep $'^\003' "$tmp" 2>/dev/null | sed $'s/^\003//' || true

    rm -f "$tmp"
    printf '\n'
    note "summary: ${found} found · ${blocked} blocked/unknown · ${missing} not found · of ${total} checked"
    pause
}

# =============================================================================
#  4 · EMAIL SCAN
# =============================================================================
fn_email() {
    printf '\n%sEmail address:%s ' "$CYAN" "$NC"
    read -r mail
    [[ -z "$mail" ]] && return
    title "EMAIL SCAN: $mail"

    if [[ ! "$mail" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        printf '  %s[!] invalid email syntax%s\n' "$RED" "$NC"
        pause; return
    fi
    note "syntax: valid"

    local dom="${mail##*@}"
    printf '\n%s[ mx records · %s ]%s\n' "$YELLOW" "$dom" "$NC"
    local mx; mx=$(dns_query MX "$dom")
    [[ -z "$mx" ]] && note "no MX records — domain cannot receive mail" || printf '%s\n' "$mx" | sed 's/^/  /'

    printf '\n%s[ spf / dmarc ]%s\n' "$YELLOW" "$NC"
    local spf dmarc
    spf=$(dns_query TXT "$dom" | grep -i 'v=spf1')
    dmarc=$(dns_query TXT "_dmarc.$dom" | grep -i 'v=DMARC1')
    [[ -n "$spf" ]]   && printf '  SPF   : %s\n' "$spf"   || note "SPF   : not found"
    [[ -n "$dmarc" ]] && printf '  DMARC : %s\n' "$dmarc" || note "DMARC : not found"

    printf '\n%s[ gravatar ]%s\n' "$YELLOW" "$NC"
    local hash code
    hash=$(md5_of "$(printf '%s' "$mail" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')")
    if [[ "$hash" == "unavailable" ]]; then
        note "no md5 utility available"
    else
        code=$(http_code "https://www.gravatar.com/avatar/${hash}?d=404")
        if [[ "$code" == "200" ]]; then
            printf '  %s[+] gravatar exists%s  https://www.gravatar.com/avatar/%s\n' "$GREEN" "$NC" "$hash"
        else
            note "no gravatar linked to this address"
        fi
    fi

    printf '\n'
    note "breach check (manual): https://haveibeenpwned.com/account/$mail"
    pause
}

# =============================================================================                                    coded by shcrypta27
#  5 · PHONE NUMBER SCAN
# =============================================================================
fn_phone() {
    printf '\n%sPhone number (with country code, e.g. +31612345678):%s ' "$CYAN" "$NC"
    read -r phone
    [[ -z "$phone" ]] && return
    title "PHONE SCAN: $phone"

    local digits="${phone//[^0-9]/}"
    if [[ ${#digits} -lt 7 ]]; then
        printf '  %s[!] too short to be a valid number%s\n' "$RED" "$NC"
        pause; return
    fi

    local cc="" country=""
    case "$digits" in
        1*)                                    cc="1";   country="USA / Canada (NANP)" ;;
        7*)                                    cc="7";   country="Russia / Kazakhstan" ;;
        20*)                                   cc="20";  country="Egypt" ;;
        27*)                                   cc="27";  country="South Africa" ;;
        30*)                                   cc="30";  country="Greece" ;;
        31*)                                   cc="31";  country="Netherlands" ;;
        32*)                                   cc="32";  country="Belgium" ;;
        33*)                                   cc="33";  country="France" ;;
        34*)                                   cc="34";  country="Spain" ;;
        39*)                                   cc="39";  country="Italy" ;;
        40*)                                   cc="40";  country="Romania" ;;
        41*)                                   cc="41";  country="Switzerland" ;;
        43*)                                   cc="43";  country="Austria" ;;
        44*)                                   cc="44";  country="United Kingdom" ;;
        45*)                                   cc="45";  country="Denmark" ;;
        46*)                                   cc="46";  country="Sweden" ;;
        47*)                                   cc="47";  country="Norway" ;;
        48*)                                   cc="48";  country="Poland" ;;
        49*)                                   cc="49";  country="Germany" ;;
        51*)                                   cc="51";  country="Peru" ;;
        52*)                                   cc="52";  country="Mexico" ;;
        54*)                                   cc="54";  country="Argentina" ;;
        55*)                                   cc="55";  country="Brazil" ;;
        56*)                                   cc="56";  country="Chile" ;;
        57*)                                   cc="57";  country="Colombia" ;;
        60*)                                   cc="60";  country="Malaysia" ;;
        61*)                                   cc="61";  country="Australia" ;;
        62*)                                   cc="62";  country="Indonesia" ;;
        63*)                                   cc="63";  country="Philippines" ;;
        64*)                                   cc="64";  country="New Zealand" ;;
        65*)                                   cc="65";  country="Singapore" ;;
        66*)                                   cc="66";  country="Thailand" ;;
        81*)                                   cc="81";  country="Japan" ;;
        82*)                                   cc="82";  country="South Korea" ;;
        84*)                                   cc="84";  country="Vietnam" ;;
        86*)                                   cc="86";  country="China" ;;
        90*)                                   cc="90";  country="Turkey" ;;
        91*)                                   cc="91";  country="India" ;;
        92*)                                   cc="92";  country="Pakistan" ;;
        93*)                                   cc="93";  country="Afghanistan" ;;
        94*)                                   cc="94";  country="Sri Lanka" ;;
        98*)                                   cc="98";  country="Iran" ;;
        212*)                                  cc="212"; country="Morocco" ;;
        213*)                                  cc="213"; country="Algeria" ;;
        216*)                                  cc="216"; country="Tunisia" ;;
        234*)                                  cc="234"; country="Nigeria" ;;
        254*)                                  cc="254"; country="Kenya" ;;
        351*)                                  cc="351"; country="Portugal" ;;
        352*)                                  cc="352"; country="Luxembourg" ;;
        353*)                                  cc="353"; country="Ireland" ;;
        358*)                                  cc="358"; country="Finland" ;;
        370*)                                  cc="370"; country="Lithuania" ;;
        371*)                                  cc="371"; country="Latvia" ;;
        372*)                                  cc="372"; country="Estonia" ;;
        380*)                                  cc="380"; country="Ukraine" ;;
        420*)                                  cc="420"; country="Czech Republic" ;;
        421*)                                  cc="421"; country="Slovakia" ;;
        *)                                     cc="?";   country="unknown" ;;
    esac

    row "country"   "$country"
    row "dial code" "+$cc"
    row "e.164"     "+${digits}"
    row "digits"    "${#digits}"
    if [[ "$cc" != "?" && ${#digits} -gt ${#cc} ]]; then
        row "national" "${digits:${#cc}}"
    fi

    printf '\n%s[ manual lookups ]%s\n' "$YELLOW" "$NC"
    note "truecaller  : https://www.truecaller.com/search/$(printf '%s' "$country" | tr 'A-Z' 'a-z' | tr -d ' /')/${digits}"
    note "google       : https://www.google.com/search?q=%22%2B${digits}%22"
    note "numlookup    : https://www.numlookup.com/?number=%2B${digits}"
    pause
}

# =============================================================================
#  6 · WHOIS LOOKUP
# =============================================================================
fn_whois() {
    printf '\n%sDomain or IP:%s ' "$CYAN" "$NC"
    read -r raw
    [[ -z "$raw" ]] && return
    local dom; dom=$(clean_domain "$raw")
    title "WHOIS: $dom"

    if have whois; then
        whois "$dom" 2>/dev/null | sed 's/^/  /'
    else
        printf '  %s[!] whois is not installed%s\n' "$RED" "$NC"
        note "install with:  sudo apt install whois   ·   pkg install whois   ·   brew install whois"
    fi
    pause
}

# =============================================================================
#  7 · GOOGLE DORK BUILDER
# =============================================================================
fn_dork() {
    printf '\n%sTarget domain:%s ' "$CYAN" "$NC"
    read -r raw
    [[ -z "$raw" ]] && return
    local dom; dom=$(clean_domain "$raw")
    title "GOOGLE DORKS: $dom"

    local dorks=(
        "site:${dom}"
        "site:${dom} filetype:pdf"
        "site:${dom} filetype:xls OR filetype:xlsx OR filetype:csv"
        "site:${dom} ext:sql OR ext:bak OR ext:log OR ext:env"
        "site:${dom} inurl:admin OR inurl:login OR inurl:dashboard"
        "site:${dom} intitle:index.of"
        "site:${dom} intext:\"password\" OR intext:\"api_key\""
        "site:${dom} -www"
        "\"@${dom}\" -site:${dom}"
        "site:pastebin.com \"${dom}\""
        "site:github.com \"${dom}\""
        "site:trello.com \"${dom}\""
        "site:docs.google.com \"${dom}\""
        "site:linkedin.com \"${dom}\""
        "site:shodan.io \"${dom}\""
    )

    local d
    for d in "${dorks[@]}"; do
        printf '\n  %s▸ %s%s\n' "$BOLD" "$d" "$NC"
        printf '    %shttps://www.google.com/search?q=%s%s\n' \
            "$DIM" "$(printf '%s' "$d" | sed 's/ /+/g; s/"/%22/g; s/:/%3A/g')" "$NC"
    done
    pause
}

# =============================================================================
#  8 · COMMON PORT CHECK
# =============================================================================
port_open() {
    local h="$1" p="$2"
    if have timeout; then
        timeout 2 bash -c "exec 3<>/dev/tcp/$h/$p" 2>/dev/null
    else
        (exec 3<>/dev/tcp/$h/$p) 2>/dev/null
    fi
}

fn_ports() {
    printf '\n%sHost (IP or domain):%s ' "$CYAN" "$NC"
    read -r host
    [[ -z "$host" ]] && return
    title "PORT CHECK: $host"

    if (( STEALTH )); then
        note "warning: raw TCP checks bypass Tor — the target will see your real IP."
        note "Tor does not proxy arbitrary ports; only 80/443/22/etc. are permitted on most exits."
        printf '  %scontinue anyway? [y/N]:%s ' "$YELLOW" "$NC"
        read -r ans
        [[ ! "$ans" =~ ^[Yy]$ ]] && return
    fi

    local ports=(21 22 23 25 53 80 110 143 443 445 993 995 1433 1521 2049 3306 3389 5432 5900 6379 8080 8443 9200 27017)
    have timeout || note "no 'timeout' binary — filtered ports may hang for a while"
    printf '\n'

    local p
    for p in "${ports[@]}"; do
        if port_open "$host" "$p"; then
            printf '  %s[ OPEN ]%s  %s\n' "$GREEN" "$NC" "$p"
        fi
    done
    printf '\n'
    note "only open ports are listed — closed/filtered are hidden"
    pause
}

# =============================================================================
#  USAGE  (for -0 / -h / -help / --help)
# =============================================================================
usage() {
    apply_palette
    banner
    printf '\n  %sUSAGE%s\n\n' "$BOLD" "$NC"
    printf '    bash %s [option]\n\n' "$(basename "$0")"
    printf '  %sOPTIONS%s\n\n' "$BOLD" "$NC"
    printf '    %s-1%s      IP Address Scan\n'           "$NUMCOL" "$NC"
    printf '    %s-2%s      Domain Scan\n'               "$NUMCOL" "$NC"
    printf '    %s-3%s      Username Search  %s(210+ sites)%s\n' "$NUMCOL" "$NC" "$DIM" "$NC"
    printf '    %s-4%s      Email Scan\n'                "$NUMCOL" "$NC"
    printf '    %s-5%s      Phone Number Scan\n'         "$NUMCOL" "$NC"
    printf '    %s-6%s      WHOIS Lookup\n'              "$NUMCOL" "$NC"
    printf '    %s-7%s      Google Dork Builder\n'       "$NUMCOL" "$NC"
    printf '    %s-8%s      Common Port Check\n'         "$NUMCOL" "$NC"
    printf '    %s-9%s      Enter interactive menu in stealth mode\n' "$NUMCOL" "$NC"
    printf '    %s-0%s      Show this help\n'            "$NUMCOL" "$NC"
    printf '    %s-h%s      Show this help\n'            "$NUMCOL" "$NC"
    printf '    %s-help%s   Show this help\n'            "$NUMCOL" "$NC"
    printf '    %s--help%s  Show this help\n'            "$NUMCOL" "$NC"
    printf '\n  %sIf no option is given, the interactive menu is shown.%s\n\n' "$DIM" "$NC"
}

# =============================================================================
#  MAIN
# =============================================================================
trap 'kill $(jobs -p) 2>/dev/null; printf "\n%s  bye.%s\n" "$BLUE" "$NC"; exit 0' INT

if ! have curl; then
    apply_palette
    printf '%s[!] curl is required but not installed. aborting.%s\n' "$RED" "$NC"
    exit 1
fi

# ── CLI dispatch ─────────────────────────────────────────────────────────────
case "${1:-}" in
    -1) apply_palette; CLI_MODE=1; fn_ip;       exit 0 ;;
    -2) apply_palette; CLI_MODE=1; fn_domain;   exit 0 ;;
    -3) apply_palette; CLI_MODE=1; fn_username; exit 0 ;;
    -4) apply_palette; CLI_MODE=1; fn_email;    exit 0 ;;
    -5) apply_palette; CLI_MODE=1; fn_phone;    exit 0 ;;
    -6) apply_palette; CLI_MODE=1; fn_whois;    exit 0 ;;
    -7) apply_palette; CLI_MODE=1; fn_dork;     exit 0 ;;
    -8) apply_palette; CLI_MODE=1; fn_ports;    exit 0 ;;
    -9) STEALTH=1 ;;
    -0|-h|-help|--help) usage; exit 0 ;;
    "")  : ;;
    *)   apply_palette; printf '%s[!] unknown option: %s%s\n' "$RED" "$1" "$NC"
         printf '    run with %s-help%s or %s--help%s for usage\n' "$NUMCOL" "$NC" "$NUMCOL" "$NC"
         exit 1 ;;
esac

# apply stealth palette + Tor probe if -9 was used
if (( STEALTH )); then
    apply_palette
    check_tor
    printf '  %sstealth mode engaged%s\n' "$DIM" "$NC"
    sleep 1
fi

# ── interactive loop ─────────────────────────────────────────────────────────
while true; do
    apply_palette
    banner
    menu
    read -r choice
    case "$choice" in
        1)  fn_ip ;;
        2)  fn_domain ;;
        3)  fn_username ;;
        4)  fn_email ;;
        5)  fn_phone ;;
        6)  fn_whois ;;
        7)  fn_dork ;;
        8)  fn_ports ;;
        9)
            if (( STEALTH )); then
                STEALTH=0
                TOR_AVAILABLE=0
                apply_palette
                printf '\n  %sleaving stealth mode…%s\n' "$DIM" "$NC"
                sleep 1
            else
                STEALTH=1
                apply_palette
                check_tor
                printf '  %sstealth mode engaged%s\n' "$DIM" "$NC"
                sleep 1
            fi
            ;;
        0)  printf '\n%s  bye.%s\n\n' "$BLUE" "$NC"; exit 0 ;;
        *)  printf '\n  %s[!] invalid option — choose 0-9%s\n' "$RED" "$NC"; sleep 1 ;;
    esac
done
# thx for using :)
