# Zerk Play 2.0: an Emby / Jellyfin client for Windows and Android TV, built around discovery and Jellyseerr/Overseerr requests

Hi all,

I've been building **Zerk Play**, a client for Emby (and now Jellyfin) that runs on **Windows** and **Android TV / Google TV**. Version 2.0 is a full rewrite, and it's the first build I'm sharing publicly.

The goal was simple: when I open the app I want to find something to watch, not scroll a library grid. If the thing I want isn't on the server yet, I want to request it from the same screen instead of switching to another app.

[screenshot: 01-home-hero.png]

---

## Discovery first

Home is built from your watch history, not just "Latest added":

- **Because you watched…** suggestions based on what you actually finished
- **What are you in the mood for?** theme rows like *Coming of age*, *Against all odds*, *Whodunits* and *Heists & cons*, each showing how many titles you already have
- **Picked for you**, plus rows built from your taste (*Because you like Action · Comedy*)
- **Top 10 trending**, with a big-number row like the streaming services have

[screenshot: 02-because-you-watched-request.png]
[screenshot: 03-mood-rows.png]
[screenshot: 04-top10-trending.png]

Every title has **tags** (from TMDB keywords: *Heist*, *Hitman*, *Based on a true story*…). Open a tag to see everything that matches, starting with what's already in your library. Each details page also has **More like this**, and trailers play in the background while you read.

[screenshot: 08-title-details-trailer.png]
[screenshot: 10-tag-page.png]

There's also a **Discover** tab (trending, popular, coming soon), a **Calendar** of upcoming releases, and **Collections** built from TMDB (*The Fast and the Furious Collection*…), even if your server doesn't group them.

## Requests built in (Jellyseerr / Overseerr)

Connect Jellyseerr or Overseerr and titles you don't have show up right next to the ones you do:

- A **Request** badge on anything not in your library, in every row: home, Discover, search, More like this
- One **Request** page: pick the seasons, watch the trailer, done
- **Search** shows your library first, then a *Not in your library* row you can request from
- **Requested** and **Awaiting release** badges, so you can see what's on the way

[screenshot: 11-request-page.png]
[screenshot: 16-search-request-not-in-library.png]
[screenshot: 14-coming-soon-requested.png]

## Playback

- **Windows:** mpv (libmpv, gpu-next on D3D11) with real **HDR** output. It can switch Windows HDR on for HDR videos and back off afterwards. Audio passthrough to your receiver (TrueHD, DTS-HD MA, EAC3…).
- **Android TV:** a native Media3 player with an FFmpeg audio decoder, plus passthrough settings for your TV / soundbar / receiver.
- **Versions:** if a movie has several files (1080p, 2160p Dolby Vision…), you can pick one and the app remembers your choice.
- **Skip intro**, manually or automatically.
- **Subtitles:** a *Smart* mode (your language, or forced subtitles for foreign dialogue), size and style options, and a delay setting.
- TMDB metadata **in your language** (titles, descriptions, logos, artwork) without touching your server's libraries.

## Live TV

Add your own Xtream Codes IPTV account to get a proper **TV guide**: channel groups, an EPG timeline and what's on now. Live TV works next to your movie library in the same app.

[screenshot: 17-live-tv-guide.png]

## Made for the couch

The whole UI is driven by **D-pad / remote / keyboard** first. It works on Windows too: plug in a gamepad or use the arrow keys, and the mouse cursor hides itself until you move it again. The mouse still works everywhere, with hover and wheel scrolling.

Setup on a TV is painless: **scan a QR code with your phone** and fill in the server, TMDB key and Jellyseerr details there instead of typing with a remote.

[screenshot: 20-library-movies.png]

---

## Download

- **Windows 10/11 (installer):** https://play.zerk.cloud/web/downloads/ZerkPlay-Public-Windows-setup.exe
- **Android TV / Google TV (APK, sideload):** https://play.zerk.cloud/web/downloads/ZerkPlay-Public-Android.apk

On first start you choose **Emby or Jellyfin**, sign in, and optionally add a **TMDB API key** (free) and your **Jellyseerr/Overseerr** address and API key. Everything is optional apart from the server.

## Good to know

- **Jellyfin support is brand new.** I developed against Emby and have only tested Jellyfin lightly. Please report anything that breaks.
- The APK isn't on the Play Store: install it with Downloader, Send Files to TV, or adb.
- Some features in my own setup (Watch together, profiles / My list, live football scores) need a companion server and **aren't in this public build**.
- Tested on Windows 11 and a Chromecast with Google TV 4K. Other Android TV boxes should work, but I'd love to hear how it runs on yours.

Feedback, bug reports and feature ideas are very welcome. Thanks for trying it!
