Config = Config or {}

-- One chip is installed on one vehicle. Owned vehicles use a stable vehicle ID
-- when the active framework exposes one through rs_bridge. Other vehicles keep
-- their chip for the lifetime of that network entity only.
Config.DefaultProfile           = 'Balanced'
Config.PersistentPlateFallback = false -- only enable if plates are guaranteed unique
Config.StateBagKey              = 'rsTunerchip'

-- Canonical inventory names. The server consumes these only after it validates
-- the live driver, vehicle, pending action, and inventory item.
Config.UseableItems = { 'tunerchip' }
Config.RemoverItems = { 'tunerchip_remover' }
Config.ConsumeInstaller = true
Config.ConsumeRemover   = true

-- Optional server-to-server installers. These resources still validate and
-- charge the work order; rs-tunerchip independently revalidates the live
-- driver, vehicle, routing bucket, class and speed before saving the chip.
Config.CustomsInstallers = {
    'rs-lscustoms',
    'rs-zombielscustoms',
}

Config.InstallMs = 2500
Config.RemoveMs  = 1800
Config.ActionCooldownMs = 350

-- Installing or uninstalling while rolling is unsafe. Profile changes use a
-- smooth transition and can be made at low road speed.
Config.MaxInstallSpeedKph   = 5.0
Config.MaxConfigureSpeedKph = 25.0

-- Smooth handling transition duration. Set to 0 for instant changes.
Config.TransitionMs = 850
Config.ReassertHandlingMs = 1500

-- 0-7 are road cars, 9 off-road, and 12 vans. Motorcycles are deliberately
-- excluded: car traction and steering fields do not create a safe bike tune.
Config.AllowedVehicleClasses = { 0, 1, 2, 3, 4, 5, 6, 7, 9, 12 }

Config.ToggleKey     = 'F5'
Config.MenuKey       = 'F10'
Config.ToggleCommand = 'drift'
Config.MenuCommand   = 'driftmenu'
Config.StatusCommand = 'driftstatus'

Config.Msg = {
    needDriver       = 'Sit in the driver seat first.',
    classBlocked     = 'This vehicle class cannot use the drift chip.',
    notInstalled     = 'This vehicle does not have an RS Drift Chip installed. Use a tuner chip while stopped.',
    alreadyInstalled = 'This vehicle already has an RS Drift Chip installed.',
    installing       = 'Installing RS Drift Chip...',
    installCanceled  = 'Drift chip installation canceled.',
    installed        = 'RS Drift Chip installed on this vehicle.',
    removing         = 'Removing RS Drift Chip...',
    removeCanceled   = 'Drift chip removal canceled.',
    removed          = 'RS Drift Chip removed and stock handling restored.',
    itemMissing      = 'The required item is no longer in your inventory.',
    tooFastInstall   = 'Stop the vehicle before installing or removing the chip.',
    tooFastTune      = 'Slow below 25 km/h before changing the drift tune.',
    enabled          = 'Drift enabled',
    disabled         = 'Drift disabled',
    profileSaved     = 'Drift profile saved to this vehicle.',
    statusOff        = 'The chip is installed, but drift mode is off.',
    menuTitle        = 'RS Drift Controller',
    serverRejected   = 'The drift controller could not verify this vehicle. Try again from the driver seat.',
}

-- Profile order is deliberate: the blended Arcade tune sits beside the smooth
-- baseline, specialist options follow, and Rockstar Native remains separate.
Config.ModeOrder = { 'Balanced', 'Arcade', 'JDM', 'Muscle', 'Takeover', 'Pursuit', 'OEM', 'NativeX' }

-- All values scale from the live vehicle's stock handling. This is much safer
-- than copying absolute handling.meta values between vehicles.
--
-- mult[field]  = stock value multiplier
-- add[field]   = small offset after the multiplier (used when stock is zero)
-- clamp[field] = final absolute { min, max }
-- power        = SetVehicleEnginePowerMultiplier percentage bonus
-- torque       = SetVehicleEngineTorqueMultiplier multiplier
-- driftTyres   = Rockstar drift tires (build 2372+); restored on disable
-- reduceGrip   = GTA's extreme loose-grip flag; intentionally false by default
Config.Modes = {
    Balanced = {
        label = 'Balanced Street',
        desc = 'Recommended. Progressive breakaway, stable transitions, easy recovery.',
        mult = {
            fTractionCurveMin               = 0.90,
            fTractionCurveMax               = 0.93,
            fTractionCurveLateral           = 1.06,
            fLowSpeedTractionLossMult       = 1.12,
            fTractionLossMult               = 1.00,
            fSteeringLock                   = 1.12,
            fTractionBiasFront              = 0.99,
            fDriveInertia                   = 1.12,
            fInitialDriveForce              = 1.06,
            fClutchChangeRateScaleUpShift   = 1.35,
            fClutchChangeRateScaleDownShift = 1.35,
            fHandBrakeForce                 = 1.08,
        },
        add = { fCamberStiffnesss = 0.025 },
        clamp = {
            fTractionCurveMin = { 1.45, 2.60 },
            fTractionCurveMax = { 1.65, 2.85 },
            fTractionCurveLateral = { 18.0, 27.0 },
            fSteeringLock = { 34.0, 58.0 },
            fTractionBiasFront = { 0.44, 0.56 },
            fCamberStiffnesss = { 0.0, 0.10 },
        },
        power = 10.0,
        torque = 1.07,
        driftTyres = false,
        reduceGrip = false,
    },

    Arcade = {
        label = 'Arcade GTA Native',
        desc = 'Native drift tires blended with Balanced, JDM, Muscle, and Takeover control.',
        mult = {
            -- The four specialist profiles are deliberately damped toward
            -- stock before native drift tires are added. This keeps the rear
            -- loose without stacking their full grip reductions on the native
            -- tire behavior.
            fTractionCurveMin               = 0.93,
            fTractionCurveMax               = 0.95,
            fTractionCurveLateral           = 1.04,
            fLowSpeedTractionLossMult       = 1.14,
            fTractionLossMult               = 1.01,
            fSteeringLock                   = 1.16,
            fTractionBiasFront              = 0.98,
            fDriveInertia                   = 1.16,
            fInitialDriveForce              = 1.09,
            fClutchChangeRateScaleUpShift   = 1.45,
            fClutchChangeRateScaleDownShift = 1.45,
            fHandBrakeForce                 = 1.11,
        },
        add = { fCamberStiffnesss = 0.035 },
        clamp = {
            fTractionCurveMin = { 1.45, 2.55 },
            fTractionCurveMax = { 1.65, 2.78 },
            fTractionCurveLateral = { 18.5, 28.0 },
            fSteeringLock = { 36.0, 62.0 },
            fTractionBiasFront = { 0.43, 0.55 },
            fCamberStiffnesss = { 0.0, 0.09 },
        },
        power = 15.0,
        torque = 1.11,
        driftTyres = true,
        reduceGrip = false,
    },

    JDM = {
        label = 'JDM Technical',
        desc = 'Sharper response and more angle without an abrupt loss of rear grip.',
        mult = {
            fTractionCurveMin               = 0.87,
            fTractionCurveMax               = 0.90,
            fTractionCurveLateral           = 1.08,
            fLowSpeedTractionLossMult       = 1.18,
            fTractionLossMult               = 1.02,
            fSteeringLock                   = 1.16,
            fTractionBiasFront              = 0.98,
            fDriveInertia                   = 1.20,
            fInitialDriveForce              = 1.08,
            fClutchChangeRateScaleUpShift   = 1.50,
            fClutchChangeRateScaleDownShift = 1.50,
            fHandBrakeForce                 = 1.12,
        },
        add = { fCamberStiffnesss = 0.040 },
        clamp = {
            fTractionCurveMin = { 1.40, 2.50 },
            fTractionCurveMax = { 1.60, 2.75 },
            fTractionCurveLateral = { 18.5, 28.0 },
            fSteeringLock = { 36.0, 62.0 },
            fTractionBiasFront = { 0.43, 0.55 },
            fCamberStiffnesss = { 0.0, 0.10 },
        },
        power = 14.0,
        torque = 1.10,
        driftTyres = false,
        reduceGrip = false,
    },

    Muscle = {
        label = 'Muscle Torque',
        desc = 'Longer power-over slides with controlled torque and recoverable steering.',
        mult = {
            fTractionCurveMin               = 0.84,
            fTractionCurveMax               = 0.88,
            fTractionCurveLateral           = 1.08,
            fLowSpeedTractionLossMult       = 1.25,
            fTractionLossMult               = 1.03,
            fSteeringLock                   = 1.15,
            fTractionBiasFront              = 0.97,
            fDriveInertia                   = 1.18,
            fInitialDriveForce              = 1.11,
            fClutchChangeRateScaleUpShift   = 1.40,
            fClutchChangeRateScaleDownShift = 1.40,
            fHandBrakeForce                 = 1.10,
        },
        add = { fCamberStiffnesss = 0.050 },
        clamp = {
            fTractionCurveMin = { 1.35, 2.45 },
            fTractionCurveMax = { 1.55, 2.70 },
            fTractionCurveLateral = { 18.5, 28.0 },
            fSteeringLock = { 36.0, 62.0 },
            fTractionBiasFront = { 0.42, 0.55 },
            fCamberStiffnesss = { 0.0, 0.10 },
        },
        power = 18.0,
        torque = 1.13,
        driftTyres = false,
        reduceGrip = false,
    },

    Takeover = {
        label = 'Takeover Angle',
        desc = 'Easy initiation and big angle with controlled breakaway and recovery.',
        mult = {
            fTractionCurveMin               = 0.82,
            fTractionCurveMax               = 0.86,
            fTractionCurveLateral           = 1.10,
            fLowSpeedTractionLossMult       = 1.30,
            fTractionLossMult               = 1.04,
            fSteeringLock                   = 1.20,
            fTractionBiasFront              = 0.96,
            fDriveInertia                   = 1.22,
            fInitialDriveForce              = 1.10,
            fClutchChangeRateScaleUpShift   = 1.55,
            fClutchChangeRateScaleDownShift = 1.55,
            fHandBrakeForce                 = 1.15,
        },
        add = { fCamberStiffnesss = 0.060 },
        clamp = {
            fTractionCurveMin = { 1.30, 2.35 },
            fTractionCurveMax = { 1.50, 2.60 },
            fTractionCurveLateral = { 19.0, 29.0 },
            fSteeringLock = { 38.0, 64.0 },
            fTractionBiasFront = { 0.42, 0.54 },
            fCamberStiffnesss = { 0.0, 0.10 },
        },
        power = 16.0,
        torque = 1.12,
        driftTyres = false,
        reduceGrip = false,
    },

    Pursuit = {
        label = 'Pursuit Hybrid',
        desc = 'Near-stock grip with extra rotation for chases and normal city driving.',
        mult = {
            fTractionCurveMin               = 0.97,
            fTractionCurveMax               = 0.98,
            fTractionCurveLateral           = 1.02,
            fLowSpeedTractionLossMult       = 1.04,
            fTractionLossMult               = 1.00,
            fSteeringLock                   = 1.08,
            fTractionBiasFront              = 1.00,
            fDriveInertia                   = 1.10,
            fInitialDriveForce              = 1.08,
            fClutchChangeRateScaleUpShift   = 1.30,
            fClutchChangeRateScaleDownShift = 1.30,
            fHandBrakeForce                 = 1.04,
        },
        add = { fCamberStiffnesss = 0.015 },
        clamp = {
            fTractionCurveMin = { 1.55, 2.75 },
            fTractionCurveMax = { 1.80, 3.00 },
            fTractionCurveLateral = { 18.0, 26.0 },
            fSteeringLock = { 32.0, 56.0 },
            fTractionBiasFront = { 0.44, 0.57 },
            fCamberStiffnesss = { 0.0, 0.08 },
        },
        power = 12.0,
        torque = 1.08,
        driftTyres = false,
        reduceGrip = false,
    },

    OEM = {
        label = 'Rockstar Native',
        desc = 'Rockstar\'s native drift tires with only mild steering and powertrain support.',
        mult = {
            fSteeringLock                   = 1.10,
            fDriveInertia                   = 1.10,
            fInitialDriveForce              = 1.06,
            fClutchChangeRateScaleUpShift   = 1.30,
            fClutchChangeRateScaleDownShift = 1.30,
        },
        clamp = {
            fSteeringLock = { 34.0, 58.0 },
        },
        power = 12.0,
        torque = 1.08,
        driftTyres = true,
        reduceGrip = false,
    },

    NativeX = {
        label = 'Native X',
        desc = 'GTA V native drift tires plus a unique low-speed angle-assist tune for snappier initiations and smoother recoveries.',
        mult = {
            fTractionCurveMin               = 0.92,
            fTractionCurveMax               = 0.95,
            fTractionCurveLateral           = 1.05,
            fLowSpeedTractionLossMult       = 1.18,
            fTractionLossMult               = 1.02,
            fSteeringLock                   = 1.18,
            fTractionBiasFront              = 0.97,
            fDriveInertia                   = 1.16,
            fInitialDriveForce              = 1.10,
            fClutchChangeRateScaleUpShift   = 1.45,
            fClutchChangeRateScaleDownShift = 1.45,
            fHandBrakeForce                 = 1.14,
        },
        add = { fCamberStiffnesss = 0.028 },
        clamp = {
            fTractionCurveMin = { 1.45, 2.60 },
            fTractionCurveMax = { 1.65, 2.82 },
            fTractionCurveLateral = { 18.5, 27.5 },
            fSteeringLock = { 36.0, 62.0 },
            fTractionBiasFront = { 0.43, 0.55 },
            fCamberStiffnesss = { 0.0, 0.09 },
        },
        power = 20.0,
        torque = 1.12,
        driftTyres = true,
        reduceGrip = false,
    },
}
