# RS TunerChip — Drift Controller

A vehicle-bound drift controller for FiveM featuring eight handling profiles, a custom in-game interface, controlled installation and removal, and server-validated tune changes.

## Requirements

- FiveM with OneSync enabled.
- `ox_lib` (required).
- For inventory-based chip installation/removal: Qbox, QBCore, or ESX with a compatible inventory (including `ox_inventory` where supported by the framework).
- Inventory items registered with the names `tunerchip` and `tunerchip_remover` (unless changed in `config.lua`).

The framework and inventory integration is included in this resource. No separate compatibility resource needs to be installed.

## Install

1. Extract the archive so the folder name is `rs-tunerchip`.
2. Start your framework and inventory provider first, then `ox_lib`.
3. Register the two item names in your inventory item definitions.
4. Add `ensure rs-tunerchip` after its requirements in `server.cfg`.
5. Check `config.lua` for profile, consumption, vehicle-class and mechanic/customs settings.

```cfg
ensure ox_lib
ensure rs-tunerchip
```

## Controls

- `F5` or `/drift` — toggle the installed drift mode.
- `F10` or `/driftmenu` — open the Drift Lab interface.
- `/driftstatus` — show the current profile and handling status.

Bindings and commands can be changed in `config.lua` or through in-game key bindings.

## Vehicle state

Qbox-owned vehicles can use their stable vehicle identifier to persist a chip installation. Otherwise, installations are tied to the current network entity unless `Config.PersistentPlateFallback` is explicitly enabled. Only enable the plate fallback if your server guarantees unique plates.

For installation or removal, the server verifies the driver, networked vehicle, routing bucket, permitted vehicle class and speed. The required inventory item is checked again at completion before the change is saved.

## Testing after installation

On a test vehicle, use each inventory item, change a drift profile, toggle the mode, exit and re-enter the vehicle, and restart the resource. Verify persistence on owned vehicles and no item duplication. Test before deploying to a live server.
