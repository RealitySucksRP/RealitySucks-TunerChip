# RS Tuner Chip — Drift Controller

<a href="https://reality-sucks-rp-webstore.tebex.io/package/7391814"><img src="docs/screenshots/preview-1.webp" width="900" alt="RS Tuner Chip — Drift Controller"></a>

Install a tuner chip, pick a profile and send it sideways. Eight drift profiles apply controlled adjustments to each vehicle’s stock handling, with a dedicated controller and an option to restore the original setup. Vehicle-bound installation and mechanic exports connect the chip to your RP.

[Download the original ZIP](https://github.com/RealitySucksRP/RealitySucks-TunerChip/releases/latest/download/rs-tunerchip.zip) | [Free on Tebex](https://reality-sucks-rp-webstore.tebex.io/package/7391814) | [Watch preview](https://youtu.be/2VgFQiGvuLA?si=WnuSrLr1up_bH3ds) | [Website](https://realitysucksrp.github.io/) | [Discord](https://discord.gg/e9V3rPHySx) | [YouTube](https://www.youtube.com/@RealitySucksRP) | [All free scripts](https://reality-sucks-rp-webstore.tebex.io/category/free-scripts)

**Install folder:** `rs-tunerchip`. Download the original ZIP to retain the package folder layout. Source, configuration, licenses and included assets are provided below.

<details>
<summary>More screenshots</summary>

<img src="docs/screenshots/preview-2.webp" width="480" alt="RS Tuner Chip — Drift Controller screenshot 2">

<img src="docs/screenshots/preview-3.webp" width="480" alt="RS Tuner Chip — Drift Controller screenshot 3">

</details>

## Requirements

- An up-to-date FiveM server with OneSync enabled
- `ox_lib` for notifications and the interface helpers
- For inventory-based installation: Qbox, QBCore, or ESX with a compatible inventory (`ox_inventory`, `qb-inventory`, or the framework's own inventory)
- Register `tunerchip` and `tunerchip_remover` as inventory items

No additional cross-resource adapter is required. Item registration uses the active framework directly; inventory presence and item removal are rechecked on the server.

## Install

1. Place the resource folder at `resources/rs-tunerchip`.
2. Ensure your framework and inventory system start first, followed by `ox_lib` and `rs-tunerchip`.
3. Register the `tunerchip` and `tunerchip_remover` items with your inventory.
4. Review `config.lua` before going live.

```cfg
ensure ox_lib
ensure rs-tunerchip
```

For `ox_inventory`, use `consume = 0` so the resource can validate the driver, vehicle and item again at the end of its progress action. You can configure both items with `server = { export = 'rs-tunerchip.useTunerChip' }` for direct ox_inventory item callbacks. For Qbox, QBCore or ESX, usable items are also registered through their native framework API. Do not configure two separate activation paths for the same item.

**Vehicle persistence:** Qbox-owned vehicles use their stable `qbx_vehicles` ID and retain previously saved tuner-chip state. Without an owned-vehicle ID, the installation lasts for that network entity only. Set `Config.PersistentPlateFallback = true` only if plates on your server are guaranteed unique.

## Controls

- `F5` / `/drift` - toggle the installed drift profile
- `F10` / `/driftmenu` - open the drift controller
- `/driftstatus` - show the active profile and live slip information

Key mappings can be changed by the player through FiveM key bindings. Defaults can be changed in `config.lua`.

## Included Profiles

Balanced Street, Arcade GTA Native, JDM Technical, Muscle Torque, Takeover Angle, Pursuit Hybrid, Rockstar Native, and Native X.

Profiles are stock-relative: the script captures the current vehicle handling values and applies bounded multipliers instead of replacing the vehicle with one universal handling setup. Stock values are restored when drift mode is disabled or the resource stops.

## Customs Integration

Server resources listed in `Config.CustomsInstallers` can use:

- `exports['rs-tunerchip']:CanInstallFromCustoms(source, vehicleNetId)`
- `exports['rs-tunerchip']:InstallFromCustoms(source, vehicleNetId)`
- `exports['rs-tunerchip']:RollbackCustomsInstall(source, token)`

Only explicitly allowlisted server resources can use the customs installation flow.

## Notes

- Motorcycles and unsupported vehicle classes are blocked by default.
- Install/remove actions are revalidated server-side at completion.
- Profile changes require the player to be the live driver and below the configured speed limit.
- No webhook, remote code loader, external license token, or external account is required by this resource.
