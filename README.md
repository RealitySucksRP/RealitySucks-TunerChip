# RealitySucks TunerChip

### RS Drift Lab — vehicle-bound drift control for FiveM
![Uploading image.png…]()

<p align="center">
  <a href="https://reality-sucks-rp-webstore.tebex.io/package/7391814"><img src="https://img.shields.io/badge/GET%20IT%20FREE-TEBEX-ff6a00?style=for-the-badge" alt="Get RealitySucks TunerChip on Tebex"></a>
  <a href="https://realitysucksrp.github.io/"><img src="https://img.shields.io/badge/VISIT-REALITYSUCKSRP%20WEBSITE-111111?style=for-the-badge" alt="Visit RealitySucksRP website"></a>
  <a href="https://youtu.be/2VgFQiGvuLA?si=graywtZHip3W1FK7"><img src="https://img.shields.io/badge/WATCH-NEW%20YOUTUBE%20PREVIEW-red?style=for-the-badge" alt="Watch the new RealitySucks TunerChip preview"></a>
  <a href="https://discord.gg/e9V3rPHySx"><img src="https://img.shields.io/badge/JOIN-DISCORD-5865F2?style=for-the-badge" alt="Join RealitySucksRP Discord"></a>
</p>

I build my own FiveM systems, test them in my own server builds and keep pushing them until they feel like part of the game instead of another menu.

**RealitySucks TunerChip** is a server-authoritative per-vehicle drift controller with a custom **RS Drift Lab** interface, multiple driving profiles, controlled profile switching and vehicle-bound state.

## New TunerChip Video

**Watch:** https://youtu.be/2VgFQiGvuLA?si=graywtZHip3W1FK7

## RS Drift Lab

The current build includes a full tune-library interface with selectable profiles for different styles of drifting and vehicle behavior.

Included profiles:

- **Balanced Street** — progressive breakaway and stable recovery
- **Arcade GTA Native** — native drift behavior blended with tuned control
- **JDM Technical** — sharper response and additional angle
- **Muscle Torque** — longer power-over slides with controlled torque
- **Takeover Angle** — easy initiation and larger-angle driving
- **Pursuit Hybrid** — additional rotation while retaining more road control
- **Rockstar Native** — closer to GTA V native drift behavior
- **Native X** — native-style drift behavior with additional low-speed assistance

## Main Features

- Vehicle-bound tuner chip system
- Server-authoritative validation before important mutations
- Driver-seat and live-vehicle verification
- Routing-bucket validation
- Vehicle-class restrictions
- Install and configure speed limits
- Per-vehicle tune state
- Persistent support for compatible player-owned vehicles
- Session-based fallback for temporary vehicles
- Smooth stock-relative handling transitions
- Reassertion of active handling while the system is enabled
- Custom RS Drift Lab NUI
- Keyboard toggle and menu controls
- Framework-neutral gameplay path through `rs_bridge`

## Controls

Default controls in the current build:

- **F5** — on-road drift toggle
- **F10** — open Drift Lab menu
- **ESC** — close menu

Server owners can change the configured commands and controls.

## Dependencies

- `rs_bridge`
- `ox_lib`

The resource is designed so framework-specific behavior stays behind the bridge instead of being duplicated throughout the tuner logic.

## Installation

1. Place the resource in your FiveM resources folder.
2. Keep the folder named `rs-tunerchip`.
3. Make sure `rs_bridge` and `ox_lib` start before it.
4. Add the configured tuner-chip items to your inventory system if needed.
5. Add the resource to `server.cfg`.
6. Restart and test the profiles on a development server before changing live handling values.

Example:

```cfg
ensure ox_lib
ensure rs_bridge
ensure rs-tunerchip
```

## More RealitySucksRP

I build FiveM systems covering vehicles, racing, garages, dealerships, LS Customs, shops, weapons, phones, zombie survival, warfare, Phantom encounters, inventories, UI and framework tools.

**Website:** https://realitysucksrp.github.io/

**Tebex:** https://reality-sucks-rp-webstore.tebex.io/

**Discord:** https://discord.gg/e9V3rPHySx

**YouTube:** https://www.youtube.com/@RealitySucksRP

## Complete FiveM Servers For Sale

Although I love making scripts and running wild on GTA, I also enjoy building complete servers.

I use my own tested RealitySucksRP systems and configure the stack around what the server owner actually wants — gameplay, framework, economy, theme and direction.

- **QBCore Shell — $500**
- **Zombie Server — $700**
- **Full RP Server — $850**
- **30 days of Discord setup/support included**

**Server packages:** https://realitysucksrp.github.io/#packages

---

**Reality Sucks. Tune it anyway.**
